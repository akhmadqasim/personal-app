-- Migration number: 0001 	 2026-09-19T05:25:44.824Z
CREATE TABLE sync_meta (
  key   TEXT PRIMARY KEY,
  value INTEGER NOT NULL
);
INSERT INTO sync_meta (key, value) VALUES ('last_seq', 0);

CREATE TABLE exercise (
  id           TEXT PRIMARY KEY,
  updated_at   INTEGER NOT NULL,
  deleted_at   INTEGER,
  seq          INTEGER NOT NULL UNIQUE,
  name         TEXT NOT NULL,
  muscle_group TEXT NOT NULL,
  equipment    TEXT NOT NULL,
  image_key    TEXT,
  notes        TEXT
);

CREATE TABLE program (
  id         TEXT PRIMARY KEY,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  seq        INTEGER NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  is_active  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE program_day (
  id         TEXT PRIMARY KEY,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  seq        INTEGER NOT NULL UNIQUE,
  program_id TEXT NOT NULL REFERENCES program(id),
  name       TEXT NOT NULL,
  position   INTEGER NOT NULL
);
CREATE INDEX idx_program_day_program ON program_day(program_id);

CREATE TABLE program_exercise (
  id               TEXT PRIMARY KEY,
  updated_at       INTEGER NOT NULL,
  deleted_at       INTEGER,
  seq              INTEGER NOT NULL UNIQUE,
  program_day_id   TEXT NOT NULL REFERENCES program_day(id),
  exercise_id      TEXT NOT NULL REFERENCES exercise(id),
  position         INTEGER NOT NULL,
  target_sets      INTEGER NOT NULL,
  target_reps      INTEGER NOT NULL,
  target_weight_kg REAL,
  rest_seconds     INTEGER
);
CREATE INDEX idx_program_exercise_day ON program_exercise(program_day_id);

CREATE TABLE workout_session (
  id             TEXT PRIMARY KEY,
  updated_at     INTEGER NOT NULL,
  deleted_at     INTEGER,
  seq            INTEGER NOT NULL UNIQUE,
  started_at     INTEGER NOT NULL,
  finished_at    INTEGER,
  program_day_id TEXT REFERENCES program_day(id),
  notes          TEXT
);

CREATE TABLE workout_set (
  id          TEXT PRIMARY KEY,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER,
  seq         INTEGER NOT NULL UNIQUE,
  session_id  TEXT NOT NULL REFERENCES workout_session(id),
  exercise_id TEXT NOT NULL REFERENCES exercise(id),
  position    INTEGER NOT NULL,
  weight_kg   REAL NOT NULL,
  reps        INTEGER NOT NULL,
  rpe         REAL,
  completed   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_workout_set_session ON workout_set(session_id);
CREATE INDEX idx_workout_set_exercise ON workout_set(exercise_id);
