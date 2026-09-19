//! SQL text for the sync engine. Pure functions so they are unit-tested natively.

use serde_json::Value;

use super::table::{BASE_COLUMNS, SyncTable};
use crate::db::Row;

/// Reads the global cursor.
pub const READ_LAST_SEQ: &str = "SELECT value FROM sync_meta WHERE key = 'last_seq'";
/// Advances the cursor only if nobody else did meanwhile (`?1` new, `?2` expected old).
pub const WRITE_LAST_SEQ: &str =
    "UPDATE sync_meta SET value = ?1 WHERE key = 'last_seq' AND value = ?2";
/// Fails the batch (duplicate primary key) when the CAS in [`WRITE_LAST_SEQ`] did not apply,
/// so a concurrent sync rolls back instead of silently reusing seq numbers.
pub const GUARD_LAST_SEQ: &str = "INSERT INTO sync_meta (key, value) SELECT 'last_seq', 0 \
     WHERE (SELECT value FROM sync_meta WHERE key = 'last_seq') != ?1";

fn column_names(table: &SyncTable) -> Vec<&'static str> {
    BASE_COLUMNS
        .iter()
        .copied()
        .chain(table.columns.iter().map(|c| c.name))
        .collect()
}

/// One statement implements last-write-wins: insert when new, overwrite when the
/// incoming `updated_at` is newer, otherwise leave the server row untouched.
pub fn upsert_sql(table: &SyncTable) -> String {
    let cols = column_names(table);
    let placeholders: Vec<String> = (1..=cols.len()).map(|i| format!("?{i}")).collect();
    let assignments: Vec<String> = cols
        .iter()
        .skip(1)
        .map(|c| format!("{c} = excluded.{c}"))
        .collect();
    format!(
        "INSERT INTO {t} ({cols}) VALUES ({ph}) ON CONFLICT(id) DO UPDATE SET {set} \
         WHERE excluded.updated_at > {t}.updated_at",
        t = table.name,
        cols = cols.join(", "),
        ph = placeholders.join(", "),
        set = assignments.join(", "),
    )
}

/// Parameters for [`upsert_sql`], in the same order. Missing optional columns bind NULL.
pub fn upsert_params(table: &SyncTable, row: &Row, seq: i64) -> Vec<Value> {
    let mut params = vec![
        row.get("id").cloned().unwrap_or(Value::Null),
        row.get("updated_at").cloned().unwrap_or(Value::Null),
        row.get("deleted_at").cloned().unwrap_or(Value::Null),
        Value::from(seq),
    ];
    params.extend(
        table
            .columns
            .iter()
            .map(|c| row.get(c.name).cloned().unwrap_or(Value::Null)),
    );
    params
}

/// Rows changed after a cursor (`?1` `since_seq`, `?2` limit).
pub fn pull_sql(table: &SyncTable) -> String {
    format!(
        "SELECT {cols} FROM {t} WHERE seq > ?1 ORDER BY seq LIMIT ?2",
        cols = column_names(table).join(", "),
        t = table.name,
    )
}

/// All active rows, for exports.
pub fn export_sql(table: &SyncTable) -> String {
    format!(
        "SELECT {cols} FROM {t} WHERE deleted_at IS NULL ORDER BY seq",
        cols = column_names(table).join(", "),
        t = table.name,
    )
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use crate::sync::table::Column;
    use serde_json::json;

    const COLS: [Column; 2] = [Column::text("name", true), Column::integer("reps", true)];
    const TABLE: SyncTable = SyncTable {
        name: "t",
        columns: &COLS,
        validate: |_| Vec::new(),
    };

    #[test]
    fn upsert_sql_is_last_write_wins() {
        assert_eq!(
            upsert_sql(&TABLE),
            "INSERT INTO t (id, updated_at, deleted_at, seq, name, reps) VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at, \
             seq = excluded.seq, name = excluded.name, reps = excluded.reps WHERE excluded.updated_at > t.updated_at"
        );
    }

    #[test]
    fn upsert_params_follow_column_order_and_fill_nulls() {
        let row = json!({ "id": "a", "updated_at": 7, "name": "x", "seq": 999 });
        let params = upsert_params(&TABLE, row.as_object().unwrap(), 42);
        assert_eq!(
            params,
            vec![
                json!("a"),
                json!(7),
                Value::Null,
                json!(42),
                json!("x"),
                Value::Null
            ]
        );
    }

    #[test]
    fn pull_and_export_sql() {
        assert_eq!(
            pull_sql(&TABLE),
            "SELECT id, updated_at, deleted_at, seq, name, reps FROM t WHERE seq > ?1 ORDER BY seq LIMIT ?2"
        );
        assert_eq!(
            export_sql(&TABLE),
            "SELECT id, updated_at, deleted_at, seq, name, reps FROM t WHERE deleted_at IS NULL ORDER BY seq"
        );
    }
}
