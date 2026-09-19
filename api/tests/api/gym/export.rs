//! GET /api/gym/export

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx, TOKEN};
use crate::fixtures::{exercise, now_ms, uuid};

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial(
        "gym::export::returns_active_rows_only",
        returns_active_rows_only,
    ));
    trials.push(ctx.trial("gym::export::requires_token", requires_token));
}

async fn returns_active_rows_only(c: Client) {
    let live = uuid();
    let dead = uuid();
    let t = now_ms();
    let mut deleted = exercise(&dead, "Deleted", t);
    deleted["deleted_at"] = json!(t);
    c.sync(
        0,
        json!({ "exercise": [exercise(&live, "Live", t), deleted] }),
    )
    .await;

    let (status, body) = c.get("/api/gym/export", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body["exported_at"].as_i64().unwrap() > 0);
    for table in [
        "exercise",
        "program",
        "program_day",
        "program_exercise",
        "workout_session",
        "workout_set",
    ] {
        assert!(body["tables"][table].is_array(), "missing table {table}");
    }
    let rows = body["tables"]["exercise"].as_array().unwrap();
    assert!(rows.iter().any(|r| r["id"] == live));
    assert!(!rows.iter().any(|r| r["id"] == dead));
}

async fn requires_token(c: Client) {
    let (status, _) = c.get("/api/gym/export", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
