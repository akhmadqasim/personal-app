//! Module registry. Adding a module = add its tables and routes here.

pub mod gym;

use worker::Router;

use crate::sync::table::SyncTable;

/// Every synced table across modules, parents before children.
pub fn sync_tables() -> Vec<&'static SyncTable> {
    gym::TABLES.iter().collect()
}

/// Mounts every module's routes.
pub fn routes(router: Router<'_, ()>) -> Router<'_, ()> {
    gym::routes(router)
}
