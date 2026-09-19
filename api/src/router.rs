//! HTTP entry: auth gate, core routes, module routes, 404 fallback.

use serde_json::json;
use worker::{Env, Request, Response, Result, Router};

use crate::auth;
use crate::error::{ApiError, ApiResult};

const PUBLIC_PATHS: [&str; 1] = ["/api/health"];

/// Dispatches one request.
pub async fn handle(req: Request, env: Env) -> Result<Response> {
    if !PUBLIC_PATHS.contains(&req.path().as_str())
        && let Err(err) = auth::require(&req, &env)
    {
        return err.into_response();
    }
    let router = Router::new()
        .get("/api/health", |_, _| {
            Response::from_json(&json!({ "ok": true }))
        })
        .post_async("/api/sync", |req, ctx| async move {
            respond(crate::sync::handler::handle(req, &ctx.env).await)
        });
    crate::modules::routes(router)
        .or_else_any_method_async("/*path", |_, _| async {
            ApiError::NotFound.into_response()
        })
        .run(req, env)
        .await
}

/// Converts a handler result into the Worker's result type.
pub fn respond(result: ApiResult<Response>) -> Result<Response> {
    result.or_else(ApiError::into_response)
}
