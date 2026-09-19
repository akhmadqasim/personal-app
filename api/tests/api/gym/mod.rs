//! Gym module tests.

pub mod catalog;
pub mod export;

use libtest_mimic::Trial;

use crate::client::Ctx;

/// Adds this module's trials to the run.
pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    catalog::register(trials, ctx);
    export::register(trials, ctx);
}
