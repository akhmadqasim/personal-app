//! Bearer token gate on every route except /api/health.

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::json;

use crate::client::{Client, Ctx, TOKEN};

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial("auth::rejects_missing_token", rejects_missing_token));
    trials.push(ctx.trial("auth::rejects_wrong_token", rejects_wrong_token));
    trials.push(ctx.trial("auth::accepts_valid_token", accepts_valid_token));
    trials.push(ctx.trial(
        "auth::unknown_route_is_404_when_authorized",
        unknown_route_is_404,
    ));
}

async fn rejects_missing_token(c: Client) {
    let (status, body) = c
        .post_json("/api/sync", &json!({ "since_seq": 0 }), None)
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["code"], "unauthorized");
}

async fn rejects_wrong_token(c: Client) {
    let (status, _) = c
        .post_json("/api/sync", &json!({ "since_seq": 0 }), Some("wrong"))
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

async fn accepts_valid_token(c: Client) {
    let (status, body) = c
        .post_json("/api/sync", &json!({ "since_seq": 0 }), Some(TOKEN))
        .await;
    assert_ne!(status, StatusCode::UNAUTHORIZED, "body: {body}");
}

async fn unknown_route_is_404(c: Client) {
    let (status, body) = c.get("/api/nope", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "not_found");
}
