//! Gym module: training catalog, programs and workout logs.

mod export;
pub mod tables;
mod validate;

use worker::Router;

pub use tables::TABLES;

use crate::router::respond;

/// Extra HTTP routes owned by this module (images added later).
pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    router.get_async("/api/gym/export", |req, ctx| async move {
        respond(export::handle(req, ctx).await)
    })
}
