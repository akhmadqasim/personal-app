//! Gym tables in foreign-key order. Column order here is the bind order.
// Consumed by the sync handler from Task 7 onwards.
#![allow(dead_code)]

use crate::sync::table::{Column, SyncTable};

use super::validate;

const EXERCISE: [Column; 5] = [
    Column::text("name", true),
    Column::text("muscle_group", true),
    Column::text("equipment", true),
    Column::text("image_key", false),
    Column::text("notes", false),
];
const PROGRAM: [Column; 2] = [
    Column::text("name", true),
    Column::integer("is_active", true),
];
const PROGRAM_DAY: [Column; 3] = [
    Column::text("program_id", true),
    Column::text("name", true),
    Column::integer("position", true),
];
const PROGRAM_EXERCISE: [Column; 7] = [
    Column::text("program_day_id", true),
    Column::text("exercise_id", true),
    Column::integer("position", true),
    Column::integer("target_sets", true),
    Column::integer("target_reps", true),
    Column::real("target_weight_kg", false),
    Column::integer("rest_seconds", false),
];
const WORKOUT_SESSION: [Column; 4] = [
    Column::integer("started_at", true),
    Column::integer("finished_at", false),
    Column::text("program_day_id", false),
    Column::text("notes", false),
];
const WORKOUT_SET: [Column; 7] = [
    Column::text("session_id", true),
    Column::text("exercise_id", true),
    Column::integer("position", true),
    Column::real("weight_kg", true),
    Column::integer("reps", true),
    Column::real("rpe", false),
    Column::integer("completed", true),
];

/// All gym tables, parents before children.
pub static TABLES: [SyncTable; 6] = [
    SyncTable {
        name: "exercise",
        columns: &EXERCISE,
        validate: validate::exercise,
    },
    SyncTable {
        name: "program",
        columns: &PROGRAM,
        validate: validate::program,
    },
    SyncTable {
        name: "program_day",
        columns: &PROGRAM_DAY,
        validate: validate::program_day,
    },
    SyncTable {
        name: "program_exercise",
        columns: &PROGRAM_EXERCISE,
        validate: validate::program_exercise,
    },
    SyncTable {
        name: "workout_session",
        columns: &WORKOUT_SESSION,
        validate: validate::workout_session,
    },
    SyncTable {
        name: "workout_set",
        columns: &WORKOUT_SET,
        validate: validate::workout_set,
    },
];
