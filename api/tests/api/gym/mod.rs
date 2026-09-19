//! Gym module tests.

pub mod catalog;

use libtest_mimic::Trial;

use crate::client::Ctx;

pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    catalog::register(trials, ctx);
}
