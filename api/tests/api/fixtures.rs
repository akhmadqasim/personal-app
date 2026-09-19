//! Builders for valid rows; tests override fields as needed.

use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};

/// A fresh random row id.
pub fn uuid() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// Wall clock in milliseconds, the unit every `updated_at` uses.
pub fn now_ms() -> i64 {
    i64::try_from(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_millis(),
    )
    .expect("fits")
}

/// A valid `exercises` row.
pub fn exercise(id: &str, name: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "name": name, "muscle_group": "chest", "equipment": "barbell",
        "image_key": null, "notes": null
    })
}

/// A valid `programs` row.
pub fn program(id: &str, name: &str, updated_at: i64) -> Value {
    json!({ "id": id, "updated_at": updated_at, "deleted_at": null, "name": name, "is_active": 1 })
}

/// A valid `program_days` row belonging to `program_id`.
pub fn program_day(id: &str, program_id: &str, name: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "program_id": program_id, "name": name, "position": 0
    })
}

/// A valid `program_exercises` row linking a day to an exercise.
pub fn program_exercise(id: &str, day_id: &str, exercise_id: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "program_day_id": day_id, "exercise_id": exercise_id, "position": 0,
        "target_sets": 3, "target_reps": 10, "target_weight_kg": 60.0, "rest_seconds": 90
    })
}

/// A valid, still running `workout_sessions` row.
pub fn workout_session(id: &str, started_at: i64, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "started_at": started_at, "finished_at": null, "program_day_id": null, "notes": null
    })
}

/// A valid `workout_sets` row belonging to `session_id`.
pub fn workout_set(id: &str, session_id: &str, exercise_id: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "updated_at": updated_at, "deleted_at": null,
        "session_id": session_id, "exercise_id": exercise_id, "position": 0,
        "weight_kg": 62.5, "reps": 8, "rpe": 8.5, "completed": 1
    })
}
