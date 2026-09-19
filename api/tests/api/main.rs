//! Integration test binary: boots wrangler dev once, runs every trial, shuts down.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::missing_panics_doc)]
// The harness is written once and consumed module by module as later tasks land;
// helpers no module calls yet would otherwise read as dead code.
#![allow(dead_code)]

mod auth;
mod client;
mod fixtures;
mod health;
mod server;

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

    let conclusion = libtest_mimic::run(&args, trials);
    drop(server);
    conclusion.exit();
}
