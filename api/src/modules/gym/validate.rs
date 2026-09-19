//! Domain rules for gym rows. Types and required columns are already checked
//! by `SyncTable::check`, so these functions may trust the JSON types.

use serde_json::Value;

use crate::db::Row;

/// Allowed `exercise.equipment` values.
pub const EQUIPMENT: [&str; 6] = [
    "barbell",
    "dumbbell",
    "machine",
    "cable",
    "bodyweight",
    "other",
];
/// Allowed `exercise.muscle_group` values.
pub const MUSCLE_GROUPS: [&str; 14] = [
    "chest",
    "back",
    "shoulders",
    "biceps",
    "triceps",
    "forearms",
    "core",
    "quads",
    "hamstrings",
    "glutes",
    "calves",
    "full_body",
    "cardio",
    "other",
];

/// Rules for `exercise` rows.
pub fn exercise(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    non_blank(row, "name", &mut errors);
    one_of(row, "muscle_group", &MUSCLE_GROUPS, &mut errors);
    one_of(row, "equipment", &EQUIPMENT, &mut errors);
    errors
}

/// Rules for `program` rows.
pub fn program(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    non_blank(row, "name", &mut errors);
    flag(row, "is_active", &mut errors);
    errors
}

/// Rules for `program_day` rows.
pub fn program_day(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    non_blank(row, "name", &mut errors);
    min_int(row, "position", 0, &mut errors);
    errors
}

/// Rules for `program_exercise` rows.
pub fn program_exercise(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    min_int(row, "position", 0, &mut errors);
    min_int(row, "target_sets", 1, &mut errors);
    min_int(row, "target_reps", 1, &mut errors);
    min_num(row, "target_weight_kg", 0.0, &mut errors);
    min_int(row, "rest_seconds", 0, &mut errors);
    errors
}

/// Rules for `workout_session` rows.
pub fn workout_session(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    min_int(row, "started_at", 1, &mut errors);
    let started = row.get("started_at").and_then(Value::as_i64);
    let finished = row.get("finished_at").and_then(Value::as_i64);
    if let (Some(s), Some(f)) = (started, finished)
        && f < s
    {
        errors.push("finished_at must be >= started_at".to_owned());
    }
    errors
}

/// Rules for `workout_set` rows.
pub fn workout_set(row: &Row) -> Vec<String> {
    let mut errors = Vec::new();
    min_int(row, "position", 0, &mut errors);
    min_num(row, "weight_kg", 0.0, &mut errors);
    min_int(row, "reps", 1, &mut errors);
    if let Some(rpe) = row.get("rpe").and_then(Value::as_f64)
        && !(1.0..=10.0).contains(&rpe)
    {
        errors.push("rpe must be between 1 and 10".to_owned());
    }
    flag(row, "completed", &mut errors);
    errors
}

fn non_blank(row: &Row, col: &str, errors: &mut Vec<String>) {
    if row
        .get(col)
        .and_then(Value::as_str)
        .is_some_and(|s| s.trim().is_empty())
    {
        errors.push(format!("{col} must not be blank"));
    }
}

fn one_of(row: &Row, col: &str, allowed: &[&str], errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_str)
        && !allowed.contains(&v)
    {
        errors.push(format!("{col} must be one of: {}", allowed.join(", ")));
    }
}

fn flag(row: &Row, col: &str, errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_i64)
        && v != 0
        && v != 1
    {
        errors.push(format!("{col} must be 0 or 1"));
    }
}

/// Applies only when the column is present (optional columns may be NULL).
fn min_int(row: &Row, col: &str, min: i64, errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_i64)
        && v < min
    {
        errors.push(format!("{col} must be >= {min}"));
    }
}

fn min_num(row: &Row, col: &str, min: f64, errors: &mut Vec<String>) {
    if let Some(v) = row.get(col).and_then(Value::as_f64)
        && v < min
    {
        errors.push(format!("{col} must be >= {min}"));
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    #[allow(clippy::needless_pass_by_value)]
    fn row(v: serde_json::Value) -> Row {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn exercise_rejects_unknown_enums_and_blank_name() {
        let errors = exercise(&row(
            json!({ "name": "  ", "muscle_group": "wings", "equipment": "laser" }),
        ));
        assert_eq!(errors.len(), 3, "{errors:?}");
        assert!(
            exercise(&row(
                json!({ "name": "Bench", "muscle_group": "chest", "equipment": "barbell" })
            ))
            .is_empty()
        );
    }

    #[test]
    fn program_and_day_rules() {
        assert!(
            program(&row(json!({ "name": "PPL", "is_active": 2 })))
                .contains(&"is_active must be 0 or 1".to_owned())
        );
        assert!(
            program_day(&row(json!({ "name": "Push", "position": -1 })))
                .contains(&"position must be >= 0".to_owned())
        );
    }

    #[test]
    fn program_exercise_targets_must_be_positive() {
        let errors = program_exercise(&row(json!({
            "position": 0,
            "target_sets": 0,
            "target_reps": 0,
            "target_weight_kg": -1,
            "rest_seconds": -5
        })));
        assert_eq!(errors.len(), 4, "{errors:?}");
    }

    #[test]
    fn session_finished_after_started() {
        assert!(
            workout_session(&row(json!({ "started_at": 10, "finished_at": 5 })))
                .contains(&"finished_at must be >= started_at".to_owned())
        );
        assert!(workout_session(&row(json!({ "started_at": 10, "finished_at": null }))).is_empty());
    }

    #[test]
    fn set_rules() {
        let errors = workout_set(&row(json!({
            "position": 0,
            "weight_kg": -1,
            "reps": 0,
            "rpe": 11,
            "completed": 3
        })));
        assert_eq!(errors.len(), 4, "{errors:?}");
        assert!(
            workout_set(&row(
                json!({ "position": 0, "weight_kg": 0, "reps": 1, "rpe": 10, "completed": 0 })
            ))
            .is_empty()
        );
    }
}
