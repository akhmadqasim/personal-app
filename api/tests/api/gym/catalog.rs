//! Built-in exercise catalog seeded by migration.

use libtest_mimic::Trial;
use serde_json::json;

use crate::client::{Client, Ctx, find_row};
use crate::fixtures::now_ms;

const LAT_PULLDOWN: &str = "64957399-5838-4e90-8d8c-be7c00552f33";

/// Adds this module's trials to the run.
pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial(
        "gym::catalog::first_pull_contains_builtin_exercises",
        first_pull_contains_builtin,
    ));
    trials.push(ctx.trial(
        "gym::catalog::user_edit_of_builtin_wins",
        user_edit_of_builtin_wins,
    ));
}

async fn first_pull_contains_builtin(c: Client) {
    let all = c.pull_all(0).await;
    let builtin: Vec<_> = all["exercise"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|r| {
            r["image_key"]
                .as_str()
                .is_some_and(|k| k.starts_with("builtin/"))
        })
        .collect();
    assert!(
        builtin.len() >= 60,
        "expected the full catalog, got {}",
        builtin.len()
    );
    // `user_edit_of_builtin_wins` bumps LAT_PULLDOWN's `updated_at`, and trials may run in
    // any order, so that one row is exempt from the seed-timestamp rule.
    assert!(
        builtin
            .iter()
            .all(|r| r["id"] == LAT_PULLDOWN || r["updated_at"] == 0),
        "seed rows must keep updated_at = 0 so user edits win"
    );
    // Only the columns no trial edits: the name and notes belong to the edit trial.
    let lat = find_row(&all, "exercise", LAT_PULLDOWN).expect("Lat Pulldown seeded");
    assert_eq!(lat["muscle_group"], "back");
    assert_eq!(lat["equipment"], "cable");
    assert_eq!(lat["image_key"], "builtin/lat-pulldown");
}

async fn user_edit_of_builtin_wins(c: Client) {
    let (_, body) = c
        .sync_all(
            0,
            json!({ "exercise": [{
                "id": LAT_PULLDOWN, "updated_at": now_ms(), "deleted_at": null,
                "name": "Lat Pulldown (wide grip)", "muscle_group": "back", "equipment": "cable",
                "image_key": "builtin/lat-pulldown", "notes": "my note"
            }] }),
        )
        .await;
    assert_eq!(
        find_row(&body["pull"], "exercise", LAT_PULLDOWN).unwrap()["notes"],
        "my note"
    );
}
