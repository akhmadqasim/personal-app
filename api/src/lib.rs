//! Personal API: a modular Cloudflare Worker backing the iOS app.

mod auth;
mod db;
mod error;
mod modules;
mod router;
mod sync;

use worker::{Context, Env, Request, Response, Result, event};

#[event(start)]
fn start() {
    console_error_panic_hook::set_once();
}

#[event(fetch, respond_with_errors)]
async fn fetch(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    router::handle(req, env).await
}
