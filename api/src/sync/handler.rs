//! `POST /api/sync`: validate → atomic push → pull after cursor.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::{D1Database, Env, Request, Response};

use super::sql;
use super::table::SyncTable;
use crate::db::{self, Row};
use crate::error::{ApiError, ApiResult, FieldError};
use crate::modules;

/// Maximum rows accepted in one push.
pub const MAX_PUSH_ROWS: usize = 500;
/// Maximum rows returned in one pull (across all tables).
pub const PULL_LIMIT: usize = 500;
/// One more than [`PULL_LIMIT`], to detect `has_more` with a single query per table.
const PULL_QUERY_LIMIT: i64 = 501;

/// Request body.
#[derive(Deserialize)]
pub struct SyncRequest {
    /// Cursor from the previous response (0 on first sync).
    #[serde(default)]
    pub since_seq: i64,
    /// Dirty rows per table.
    #[serde(default)]
    pub push: BTreeMap<String, Vec<Row>>,
}

/// Response body.
#[derive(Serialize)]
pub struct SyncResponse {
    /// Cursor to send next time.
    pub seq: i64,
    /// `true` when the pull was truncated.
    pub has_more: bool,
    /// Changed rows per table (every table present, possibly empty).
    pub pull: BTreeMap<&'static str, Vec<Row>>,
}

/// HTTP handler.
pub async fn handle(mut req: Request, env: &Env) -> ApiResult<Response> {
    let body: SyncRequest = req
        .json()
        .await
        .map_err(|e| ApiError::BadRequest(format!("invalid JSON body: {e}")))?;
    let db = env.d1("DB")?;
    let tables = modules::sync_tables();
    let response = run(&db, &tables, &body).await?;
    Ok(Response::from_json(&response)?)
}

async fn run(db: &D1Database, tables: &[&SyncTable], req: &SyncRequest) -> ApiResult<SyncResponse> {
    validate_push(tables, &req.push)?;
    let last_seq = apply_push(db, tables, &req.push).await?;
    pull(db, tables, req.since_seq, last_seq).await
}

fn validate_push(tables: &[&SyncTable], push: &BTreeMap<String, Vec<Row>>) -> ApiResult<()> {
    let total: usize = push.values().map(Vec::len).sum();
    if total > MAX_PUSH_ROWS {
        return Err(ApiError::PayloadTooLarge(format!(
            "push contains {total} rows; the limit is {MAX_PUSH_ROWS}"
        )));
    }
    let mut errors = Vec::new();
    for (name, rows) in push {
        let Some(table) = tables.iter().find(|t| t.name == name) else {
            errors.push(FieldError {
                table: name.clone(),
                id: String::new(),
                message: "unknown table".into(),
            });
            continue;
        };
        for row in rows {
            let id = row
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            errors.extend(table.check(row).into_iter().map(|message| FieldError {
                table: name.clone(),
                id: id.clone(),
                message,
            }));
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(ApiError::Validation(errors))
    }
}

/// Writes pushed rows in FK order inside one atomic batch; returns the new `last_seq`.
async fn apply_push(
    db: &D1Database,
    tables: &[&SyncTable],
    push: &BTreeMap<String, Vec<Row>>,
) -> ApiResult<i64> {
    let last_seq = read_last_seq(db).await?;
    let mut statements = Vec::new();
    let mut seq = last_seq;
    for table in tables {
        let Some(rows) = push.get(table.name) else {
            continue;
        };
        let sql = sql::upsert_sql(table);
        for row in rows {
            seq += 1;
            statements.push(db::prepare(db, &sql, &sql::upsert_params(table, row, seq))?);
        }
    }
    if statements.is_empty() {
        return Ok(last_seq);
    }
    // D1 does not report the CAS below updating zero rows, so a concurrent sync that moved
    // the cursor between `read_last_seq` and this batch would silently reuse seq numbers.
    // The guard opens the batch and turns that into a primary-key clash, rolling everything
    // back. It compares against the value we read, not the one we are about to write: two
    // racing pushes of the same size compute the same new value, so checking the new value
    // after the CAS would let the loser through.
    statements.insert(
        0,
        db::prepare(db, sql::GUARD_LAST_SEQ, &[Value::from(last_seq)])?,
    );
    statements.push(db::prepare(
        db,
        sql::WRITE_LAST_SEQ,
        &[Value::from(seq), Value::from(last_seq)],
    )?);
    db.batch(statements)
        .await
        .map_err(|e| map_batch_error(&e))?;
    Ok(seq)
}

async fn read_last_seq(db: &D1Database) -> ApiResult<i64> {
    db::query_i64(db, sql::READ_LAST_SEQ, &[], "value")
        .await?
        .ok_or_else(|| ApiError::Internal("sync_meta.last_seq is missing".into()))
}

/// D1 reports constraint failures as plain text; map the two we expect.
fn map_batch_error(err: &worker::Error) -> ApiError {
    let text = err.to_string();
    if text.contains("UNIQUE constraint failed") {
        ApiError::Conflict("another sync is in progress; retry".into())
    } else if text.contains("FOREIGN KEY constraint failed") {
        ApiError::Validation(vec![FieldError {
            table: String::new(),
            id: String::new(),
            message: "a referenced row does not exist".into(),
        }])
    } else {
        ApiError::Internal(text)
    }
}

async fn pull(
    db: &D1Database,
    tables: &[&SyncTable],
    since_seq: i64,
    last_seq: i64,
) -> ApiResult<SyncResponse> {
    let params = [Value::from(since_seq), Value::from(PULL_QUERY_LIMIT)];
    let mut all: Vec<(&'static str, Row)> = Vec::new();
    for table in tables {
        let rows = db::query_rows(db, &sql::pull_sql(table), &params).await?;
        all.extend(rows.into_iter().map(|row| (table.name, row)));
    }
    all.sort_by_key(|(_, row)| row_seq(row));
    let has_more = all.len() > PULL_LIMIT;
    all.truncate(PULL_LIMIT);
    let seq = if has_more {
        all.last().map_or(since_seq, |(_, row)| row_seq(row))
    } else {
        since_seq.max(last_seq)
    };
    let mut pull: BTreeMap<&'static str, Vec<Row>> =
        tables.iter().map(|t| (t.name, Vec::new())).collect();
    for (name, row) in all {
        if let Some(bucket) = pull.get_mut(name) {
            bucket.push(row);
        }
    }
    Ok(SyncResponse {
        seq,
        has_more,
        pull,
    })
}

fn row_seq(row: &Row) -> i64 {
    row.get("seq").and_then(Value::as_i64).unwrap_or(0)
}
