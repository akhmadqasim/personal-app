//! Thin D1 helpers: bind `serde_json` values and read rows back as JSON maps.

use serde_json::{Map, Value};
use wasm_bindgen::JsValue;
use worker::{D1Database, D1PreparedStatement, Result};

/// A database row as a JSON object (column → value).
pub type Row = Map<String, Value>;

/// Converts a JSON scalar to the `JsValue` D1 expects. Arrays/objects are not
/// valid D1 parameters and become NULL.
pub fn to_js(value: &Value) -> JsValue {
    match value {
        Value::Null | Value::Array(_) | Value::Object(_) => JsValue::NULL,
        Value::Bool(b) => JsValue::from_bool(*b),
        Value::Number(n) => n.as_f64().map_or(JsValue::NULL, JsValue::from_f64),
        Value::String(s) => JsValue::from_str(s),
    }
}

/// Prepares `sql` with positional parameters (`?1`, `?2`, …).
pub fn prepare(db: &D1Database, sql: &str, params: &[Value]) -> Result<D1PreparedStatement> {
    let values: Vec<JsValue> = params.iter().map(to_js).collect();
    db.prepare(sql).bind(&values)
}

/// Runs a SELECT and returns every row as a JSON object.
pub async fn query_rows(db: &D1Database, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
    prepare(db, sql, params)?.all().await?.results::<Row>()
}

/// Runs a SELECT and returns one integer column of the first row, if any.
pub async fn query_i64(
    db: &D1Database,
    sql: &str,
    params: &[Value],
    column: &str,
) -> Result<Option<i64>> {
    prepare(db, sql, params)?.first::<i64>(Some(column)).await
}
