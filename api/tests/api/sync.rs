//! POST /api/sync — push (LWW) and pull (seq cursor).

use std::collections::HashSet;

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::{Value, json};

use crate::client::{Client, Ctx, TOKEN, find_row};
use crate::fixtures::{
    exercise, now_ms, program, program_day, program_exercise, uuid, workout_session, workout_set,
};

/// Adds this module's trials to the run.
pub fn register(trials: &mut Vec<Trial>, ctx: &Ctx) {
    trials.push(ctx.trial(
        "sync::push_then_pull_returns_row",
        push_then_pull_returns_row,
    ));
    trials.push(ctx.trial(
        "sync::cursor_excludes_older_rows",
        cursor_excludes_older_rows,
    ));
    trials.push(ctx.trial(
        "sync::same_push_twice_is_idempotent",
        same_push_twice_is_idempotent,
    ));
    trials.push(ctx.trial("sync::newer_update_wins", newer_update_wins));
    trials.push(ctx.trial("sync::older_update_is_ignored", older_update_is_ignored));
    trials.push(ctx.trial("sync::soft_delete_propagates", soft_delete_propagates));
    trials.push(ctx.trial(
        "sync::validation_error_rejects_whole_batch",
        validation_error_rejects_whole_batch,
    ));
    trials.push(ctx.trial("sync::unknown_table_is_rejected", unknown_table_is_rejected));
    trials.push(ctx.trial(
        "sync::missing_foreign_key_is_rejected",
        missing_foreign_key_is_rejected,
    ));
    trials.push(ctx.trial(
        "sync::missing_foreign_key_rolls_back_siblings",
        missing_foreign_key_rolls_back_siblings,
    ));
    trials.push(ctx.trial(
        "sync::concurrent_pushes_never_duplicate_seq",
        concurrent_pushes_never_duplicate_seq,
    ));
    trials.push(ctx.trial(
        "sync::child_and_parent_in_one_push",
        child_and_parent_in_one_push,
    ));
    trials.push(ctx.trial("sync::oversized_push_is_413", oversized_push_is_413));
    trials.push(ctx.trial("sync::malformed_json_is_400", malformed_json_is_400));
    trials.push(ctx.trial(
        "sync::non_200_page_is_returned_by_sync_all",
        non_200_page_is_returned_by_sync_all,
    ));
    trials.push(ctx.trial("sync::paginates_with_has_more", paginates_with_has_more));
    trials.push(ctx.trial(
        "sync::cursor_beyond_last_seq_self_heals",
        cursor_beyond_last_seq_self_heals,
    ));
    trials.push(ctx.trial("sync::program_chain_round_trips", program_chain_round_trips));
}

async fn push_then_pull_returns_row(c: Client) {
    let id = uuid();
    let (status, body) = c
        .sync_all(
            0,
            json!({ "exercise": [exercise(&id, "Bench Press", now_ms())] }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let row = find_row(&body["pull"], "exercise", &id).expect("pushed row echoed back");
    assert_eq!(row["name"], "Bench Press");
    assert!(row["seq"].as_i64().unwrap() > 0);
    assert!(body["seq"].as_i64().unwrap() >= row["seq"].as_i64().unwrap());
}

async fn cursor_excludes_older_rows(c: Client) {
    let a = uuid();
    let (_, first) = c
        .sync_all(0, json!({ "exercise": [exercise(&a, "A", now_ms())] }))
        .await;
    let cursor = first["seq"].as_i64().unwrap();
    let b = uuid();
    let (_, second) = c
        .sync_all(cursor, json!({ "exercise": [exercise(&b, "B", now_ms())] }))
        .await;
    assert!(find_row(&second["pull"], "exercise", &a).is_none());
    assert!(find_row(&second["pull"], "exercise", &b).is_some());
}

async fn same_push_twice_is_idempotent(c: Client) {
    let id = uuid();
    let row = exercise(&id, "Row", now_ms());
    let (_, first) = c.sync_all(0, json!({ "exercise": [row.clone()] })).await;
    let (_, second) = c.sync_all(0, json!({ "exercise": [row] })).await;
    let seq1 = find_row(&first["pull"], "exercise", &id).unwrap()["seq"].clone();
    let seq2 = find_row(&second["pull"], "exercise", &id).unwrap()["seq"].clone();
    assert_eq!(seq1, seq2, "unchanged row must keep its seq");
    let all = c.pull_all(0).await;
    assert_eq!(
        all["exercise"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|r| r["id"] == id)
            .count(),
        1
    );
}

async fn newer_update_wins(c: Client) {
    let id = uuid();
    let t = now_ms();
    c.sync(0, json!({ "exercise": [exercise(&id, "Old", t)] }))
        .await;
    let (_, body) = c
        .sync_all(0, json!({ "exercise": [exercise(&id, "New", t + 1)] }))
        .await;
    assert_eq!(
        find_row(&body["pull"], "exercise", &id).unwrap()["name"],
        "New"
    );
}

async fn older_update_is_ignored(c: Client) {
    let id = uuid();
    let t = now_ms();
    c.sync(0, json!({ "exercise": [exercise(&id, "Current", t)] }))
        .await;
    let (_, body) = c
        .sync_all(0, json!({ "exercise": [exercise(&id, "Stale", t - 1)] }))
        .await;
    let row = find_row(&body["pull"], "exercise", &id).unwrap();
    assert_eq!(row["name"], "Current");
    assert_eq!(row["updated_at"], t);
}

async fn soft_delete_propagates(c: Client) {
    let id = uuid();
    let t = now_ms();
    c.sync(0, json!({ "exercise": [exercise(&id, "Gone", t)] }))
        .await;
    let mut deleted = exercise(&id, "Gone", t + 1);
    deleted["deleted_at"] = json!(t + 1);
    let (_, body) = c.sync_all(0, json!({ "exercise": [deleted] })).await;
    assert_eq!(
        find_row(&body["pull"], "exercise", &id).unwrap()["deleted_at"],
        t + 1
    );
}

async fn validation_error_rejects_whole_batch(c: Client) {
    let good = uuid();
    let bad = uuid();
    let mut invalid = exercise(&bad, "Bad", now_ms());
    invalid["equipment"] = json!("laser");
    let (status, body) = c
        .sync(
            0,
            json!({ "exercise": [exercise(&good, "Good", now_ms()), invalid] }),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
    assert_eq!(body["errors"][0]["table"], "exercise");
    assert_eq!(body["errors"][0]["id"], bad);
    let all = c.pull_all(0).await;
    assert!(
        find_row(&all, "exercise", &good).is_none(),
        "valid row must not be written"
    );
}

async fn unknown_table_is_rejected(c: Client) {
    let (status, body) = c
        .sync(0, json!({ "secrets": [{ "id": "x", "updated_at": 1 }] }))
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["errors"][0]["table"], "secrets");
    assert_eq!(body["errors"][0]["message"], "unknown table");
}

async fn missing_foreign_key_is_rejected(c: Client) {
    let ex = uuid();
    c.sync(0, json!({ "exercise": [exercise(&ex, "Ex", now_ms())] }))
        .await;
    let set = workout_set(&uuid(), &uuid(), &ex, now_ms());
    let (status, body) = c.sync(0, json!({ "workout_set": [set] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
}

/// The batch is atomic, so a dangling FK also rolls back the valid rows beside it.
async fn missing_foreign_key_rolls_back_siblings(c: Client) {
    let sibling = uuid();
    let t = now_ms();
    let set = workout_set(&uuid(), &uuid(), &sibling, t);
    let (status, body) = c
        .sync(
            0,
            json!({
                "exercise": [exercise(&sibling, "Sibling", t)],
                "workout_set": [set]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
    let all = c.pull_all(0).await;
    assert!(
        find_row(&all, "exercise", &sibling).is_none(),
        "the valid sibling row must roll back with the batch"
    );
}

/// Two syncs racing on disjoint tables must never hand out the same `seq`: the loser's
/// batch rolls back and reports 409 instead of committing a duplicate.
async fn concurrent_pushes_never_duplicate_seq(c: Client) {
    for _ in 0..5 {
        let t = now_ms();
        let other = c.clone();
        let (left, right) = tokio::join!(
            c.sync(0, json!({ "exercise": [exercise(&uuid(), "Race", t)] })),
            other.sync(0, json!({ "program": [program(&uuid(), "Race", t)] })),
        );
        for (status, body) in [left, right] {
            assert!(
                status == StatusCode::OK || status == StatusCode::CONFLICT,
                "expected 200 or 409, got {status}: {body}"
            );
        }
    }
    let all = c.pull_all(0).await;
    let seqs: Vec<i64> = all
        .as_object()
        .unwrap()
        .values()
        .flat_map(|rows| rows.as_array().unwrap())
        .map(|row| row["seq"].as_i64().unwrap())
        .collect();
    let unique: HashSet<i64> = seqs.iter().copied().collect();
    assert_eq!(
        unique.len(),
        seqs.len(),
        "seq values must be globally unique"
    );
}

async fn child_and_parent_in_one_push(c: Client) {
    let ex = uuid();
    let session = uuid();
    let set = uuid();
    let t = now_ms();
    let (status, body) = c
        .sync_all(
            0,
            json!({
                "workout_set": [workout_set(&set, &session, &ex, t)],
                "workout_session": [workout_session(&session, t, t)],
                "exercise": [exercise(&ex, "Squat", t)]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        find_row(&body["pull"], "workout_set", &set).unwrap()["weight_kg"],
        62.5
    );
}

async fn oversized_push_is_413(c: Client) {
    let rows: Vec<Value> = (0..501)
        .map(|i| exercise(&uuid(), &format!("E{i}"), now_ms()))
        .collect();
    let (status, body) = c.sync(0, json!({ "exercise": rows })).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(body["code"], "payload_too_large");
}

async fn malformed_json_is_400(c: Client) {
    let (status, body) = c.post_text("/api/sync", "{not json", Some(TOKEN)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "bad_request");
}

/// `sync_all` must hand back a non-200 page instead of walking into a panic.
async fn non_200_page_is_returned_by_sync_all(c: Client) {
    let mut invalid = exercise(&uuid(), "Bad", now_ms());
    invalid["equipment"] = json!("laser");
    let (status, body) = c.sync_all(0, json!({ "exercise": [invalid] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
}

async fn paginates_with_has_more(c: Client) {
    let ids: Vec<String> = (0..500).map(|_| uuid()).collect();
    let rows: Vec<Value> = ids
        .iter()
        .enumerate()
        .map(|(i, id)| exercise(id, &format!("P{i}"), now_ms()))
        .collect();
    let (status, first) = c.sync(0, json!({ "exercise": rows })).await;
    assert_eq!(status, StatusCode::OK, "{first}");
    // A 501st row in its own push, so the trial does not rely on rows left by other trials.
    let (status, extra) = c
        .sync(
            0,
            json!({ "exercise": [exercise(&uuid(), "P500", now_ms())] }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{extra}");
    let (_, page) = c.sync(0, json!({})).await;
    assert_eq!(
        page["has_more"], true,
        "501 pushed rows must exceed one page"
    );
    let all = c.pull_all(0).await;
    let got = all["exercise"].as_array().unwrap();
    for id in &ids {
        assert!(got.iter().any(|r| r["id"] == *id), "missing {id}");
    }
}

/// A cursor past the server's `last_seq` (a restored or corrupted client) must snap back to
/// the server cursor instead of pulling nothing forever.
///
/// The probe is `Number.MAX_SAFE_INTEGER`, not `i64::MAX / 2`: the Worker parses the body
/// with JS `JSON.parse`, so any cursor above 2^53-1 loses precision and is rejected as 400
/// before it ever reaches the clamp.
async fn cursor_beyond_last_seq_self_heals(c: Client) {
    let far = 9_007_199_254_740_991i64;
    let (status, body) = c.sync(far, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let healed = body["seq"].as_i64().unwrap();
    assert_ne!(healed, far, "the impossible cursor must not be echoed back");
    let (status, caught_up) = c.sync_all(0, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{caught_up}");
    let server = caught_up["seq"].as_i64().unwrap();
    assert!(
        healed <= server,
        "healed cursor {healed} must not run ahead of the server cursor {server}"
    );
}

/// A whole program tree in one push: the server orders the batch by FK dependency, so the
/// client may send the tables in any order. A dangling parent is a 422 instead.
async fn program_chain_round_trips(c: Client) {
    let (prog, day, ex, link) = (uuid(), uuid(), uuid(), uuid());
    let t = now_ms();
    let (status, body) = c
        .sync_all(
            0,
            json!({
                "program_exercise": [program_exercise(&link, &day, &ex, t)],
                "exercise": [exercise(&ex, "Incline Press", t)],
                "program_day": [program_day(&day, &prog, "Push", t)],
                "program": [program(&prog, "PPL", t)]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    for (table, id) in [
        ("program", &prog),
        ("program_day", &day),
        ("exercise", &ex),
        ("program_exercise", &link),
    ] {
        let row =
            find_row(&body["pull"], table, id).unwrap_or_else(|| panic!("{table} {id} not echoed"));
        assert!(row["seq"].as_i64().unwrap() > 0, "{table} {id} has no seq");
    }

    let orphan = program_exercise(&uuid(), &uuid(), &ex, now_ms());
    let (status, body) = c.sync(0, json!({ "program_exercise": [orphan] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "validation_failed");
}
