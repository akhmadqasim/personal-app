import Foundation
import GRDB

/// The six tables that take part in sync. Their rows all carry
/// `id, updated_at, deleted_at, seq, dirty`, and they are listed in
/// foreign-key order: a parent always comes before its children, which is the
/// order the sync engine must push them in.
nonisolated enum SyncedTable: String, Sendable, CaseIterable {
    case exercise
    case program
    case programDay = "program_day"
    case programExercise = "program_exercise"
    case workoutSession = "workout_session"
    case workoutSet = "workout_set"
}

/// The local schema.
///
/// `v1` mirrors `api/migrations/0001_gym.sql` one to one, with three local
/// differences (spec §4):
///
/// - `seq` is nullable and not `UNIQUE`: the server owns that counter and a
///   row created offline has no `seq` until the first successful push.
/// - every synced table gains `dirty INTEGER NOT NULL DEFAULT 0` plus an index
///   on it, so collecting the push payload is a cheap indexed scan.
/// - the server's `sync_meta` is replaced by `sync_state`, holding the pull
///   cursor `since_seq` and `last_synced_at`.
nonisolated enum Migrations {

    /// A fresh migrator. Both `AppDatabase` entry points run it, so any
    /// connection handed out by the app is already at the latest version.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: Migrations.v1)
        }
        return migrator
    }

    /// The column names of `table`, in declaration order. Used by the schema
    /// tests and by diagnostics; it keeps `PRAGMA` handling in one place.
    static func columnNames(of table: String, in reader: any DatabaseReader) throws -> [String] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
            return rows.map { row in
                let name: String = row["name"]
                return name
            }
        }
    }

    /// The columns of `table` that accept NULL (`PRAGMA table_info.notnull = 0`).
    static func nullableColumns(of table: String, in reader: any DatabaseReader) throws -> [String] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
            return rows.compactMap { row -> String? in
                let notNull: Int = row["notnull"]
                guard notNull == 0 else { return nil }
                let name: String = row["name"]
                return name
            }
        }
    }

    /// The whole `sync_state` table as a dictionary.
    static func syncState(in reader: any DatabaseReader) throws -> [String: Int64] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM sync_state")
            var state: [String: Int64] = [:]
            for row in rows {
                let key: String = row["key"]
                let value: Int64 = row["value"]
                state[key] = value
            }
            return state
        }
    }

    // MARK: - SQL

    private static let v1 = """
        CREATE TABLE exercise (
          id           TEXT PRIMARY KEY,
          updated_at   INTEGER NOT NULL,
          deleted_at   INTEGER,
          seq          INTEGER,
          name         TEXT NOT NULL,
          muscle_group TEXT NOT NULL,
          equipment    TEXT NOT NULL,
          image_key    TEXT,
          notes        TEXT,
          dirty        INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_exercise_dirty ON exercise(dirty);

        CREATE TABLE program (
          id         TEXT PRIMARY KEY,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER,
          seq        INTEGER,
          name       TEXT NOT NULL,
          is_active  INTEGER NOT NULL DEFAULT 0,
          dirty      INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_program_dirty ON program(dirty);

        CREATE TABLE program_day (
          id         TEXT PRIMARY KEY,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER,
          seq        INTEGER,
          program_id TEXT NOT NULL REFERENCES program(id),
          name       TEXT NOT NULL,
          position   INTEGER NOT NULL,
          dirty      INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_program_day_program ON program_day(program_id);
        CREATE INDEX idx_program_day_dirty ON program_day(dirty);

        CREATE TABLE program_exercise (
          id               TEXT PRIMARY KEY,
          updated_at       INTEGER NOT NULL,
          deleted_at       INTEGER,
          seq              INTEGER,
          program_day_id   TEXT NOT NULL REFERENCES program_day(id),
          exercise_id      TEXT NOT NULL REFERENCES exercise(id),
          position         INTEGER NOT NULL,
          target_sets      INTEGER NOT NULL,
          target_reps      INTEGER NOT NULL,
          target_weight_kg REAL,
          rest_seconds     INTEGER,
          dirty            INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_program_exercise_day ON program_exercise(program_day_id);
        CREATE INDEX idx_program_exercise_dirty ON program_exercise(dirty);

        CREATE TABLE workout_session (
          id             TEXT PRIMARY KEY,
          updated_at     INTEGER NOT NULL,
          deleted_at     INTEGER,
          seq            INTEGER,
          started_at     INTEGER NOT NULL,
          finished_at    INTEGER,
          program_day_id TEXT REFERENCES program_day(id),
          notes          TEXT,
          dirty          INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_workout_session_dirty ON workout_session(dirty);

        CREATE TABLE workout_set (
          id          TEXT PRIMARY KEY,
          updated_at  INTEGER NOT NULL,
          deleted_at  INTEGER,
          seq         INTEGER,
          session_id  TEXT NOT NULL REFERENCES workout_session(id),
          exercise_id TEXT NOT NULL REFERENCES exercise(id),
          position    INTEGER NOT NULL,
          weight_kg   REAL NOT NULL,
          reps        INTEGER NOT NULL,
          rpe         REAL,
          completed   INTEGER NOT NULL DEFAULT 0,
          dirty       INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_workout_set_session ON workout_set(session_id);
        CREATE INDEX idx_workout_set_exercise ON workout_set(exercise_id);
        CREATE INDEX idx_workout_set_dirty ON workout_set(dirty);

        CREATE TABLE sync_state (
          key   TEXT PRIMARY KEY,
          value INTEGER NOT NULL
        );
        INSERT INTO sync_state (key, value) VALUES ('since_seq', 0), ('last_synced_at', 0);
        """
}
