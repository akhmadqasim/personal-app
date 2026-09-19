//! HTTP entry: auth gate, core routes, module routes, 404 fallback.

use serde_json::json;
use worker::{Env, Request, Response, Result, Router};

/// Dispatches one request.
pub async fn handle(req: Request, env: Env) -> Result<Response> {
    Router::new()
        .get("/api/health", |_, _| {
            Response::from_json(&json!({ "ok": true }))
        })
        .run(req, env)
        .await
}
