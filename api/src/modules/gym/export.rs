//! `GET /api/gym/export`: every active gym row as one JSON document, for analysis.

use std::collections::BTreeMap;

use serde_json::json;
use worker::{Date, Request, Response, RouteContext};

use super::TABLES;
use crate::db::{self, Row};
use crate::error::ApiResult;
use crate::sync::sql;

/// HTTP handler.
pub async fn handle(_req: Request, ctx: RouteContext<()>) -> ApiResult<Response> {
    let db = ctx.env.d1("DB")?;
    let mut tables: BTreeMap<&'static str, Vec<Row>> = BTreeMap::new();
    for table in &TABLES {
        tables.insert(
            table.name,
            db::query_rows(&db, &sql::export_sql(table), &[]).await?,
        );
    }
    Ok(Response::from_json(&json!({
        "exported_at": Date::now().as_millis(),
        "tables": tables,
    }))?)
}
