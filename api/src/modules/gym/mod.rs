//! Gym module: training catalog, programs and workout logs.

pub mod tables;
mod validate;

use worker::Router;

pub use tables::TABLES;

/// Extra HTTP routes owned by this module (export and images, added later).
pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    router
}
