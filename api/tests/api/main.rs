//! Integration test binary: boots wrangler dev once, runs every trial, shuts down.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::missing_panics_doc)]

mod auth;
mod client;
mod fixtures;
mod gym;
mod health;
mod server;
mod sync;

use libtest_mimic::Arguments;

fn main() {
    let mut args = Arguments::from_args();
    // All trials share one local D1 database and one dev server, so they run in order.
    args.test_threads.get_or_insert(1);

    let server = server::DevServer::start();
    let ctx = client::Ctx::new(&server.base_url());

    let mut trials = Vec::new();
    health::register(&mut trials, &ctx);
    auth::register(&mut trials, &ctx);
    // Registered before `sync` so the catalog tests' plain (non-paginating) `sync()`
    // calls see the pull's first page before `sync::paginates_with_has_more` pushes
    // 501 rows and pushes every other table's rows past the 500-row pull page.
    gym::register(&mut trials, &ctx);
    sync::register(&mut trials, &ctx);

    let conclusion = libtest_mimic::run(&args, trials);
    drop(server);
    conclusion.exit();
}
