//! Integration test binary: boots wrangler dev once, runs every trial, shuts down.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::missing_panics_doc)]

mod auth;
mod client;
mod fixtures;
mod gym;
mod health;
mod server;
mod sync;

use std::thread;
use std::time::Duration;

use libtest_mimic::Arguments;

/// Hard cap on the whole run, boot included. CI allows 20 minutes, so aborting first
/// means the dev server log and the process tree teardown still happen.
const WATCHDOG: Duration = Duration::from_mins(15);

/// Exit code the watchdog uses, so a hang is distinguishable from a failing trial.
const WATCHDOG_EXIT: i32 = 2;

fn main() {
    let mut args = Arguments::from_args();
    // All trials share one local D1 database and one dev server, so they run in order.
    args.test_threads.get_or_insert(1);

    spawn_watchdog();

    let server = server::DevServer::start();
    let ctx = client::Ctx::new(&server.base_url());

    let mut trials = Vec::new();
    health::register(&mut trials, &ctx);
    auth::register(&mut trials, &ctx);
    sync::register(&mut trials, &ctx);
    gym::register(&mut trials, &ctx);

    let conclusion = libtest_mimic::run(&args, trials);
    drop(server);
    conclusion.exit();
}

/// Aborts the process if the suite stops making progress, leaving the dev server log
/// behind and no orphan `wrangler`/`workerd` holding CI's stdout open.
fn spawn_watchdog() {
    thread::spawn(|| {
        thread::sleep(WATCHDOG);
        eprintln!("watchdog: integration suite exceeded 15 min");
        server::print_log_tail(60);
        server::kill_running_server();
        std::process::exit(WATCHDOG_EXIT);
    });
}
