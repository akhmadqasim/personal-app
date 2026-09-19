//! GET /api/health

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx};

/// Adds this module's trials to the run.
pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("health::returns_ok_without_token", returns_ok_without_token));
}

async fn returns_ok_without_token(c: Client) {
    let (status, body) = c.get("/api/health", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({ "ok": true }));
}
