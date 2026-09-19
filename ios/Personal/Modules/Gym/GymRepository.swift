import Foundation
import GRDB

/// The best set of one session, for the Progress chart.
nonisolated struct BestSet: Sendable, Equatable {
    /// Milliseconds since the epoch — the x axis.
    var sessionStartedAt: Int64
    /// Heaviest completed set of that session — the y axis.
    var weightKg: Double
}

/// Every gym read and write goes through here.
///
/// Two invariants hold for the whole app (spec §5):
///
/// - a write stamps `updated_at = clock.nowMs()` and sets `dirty = true`, so
///   the sync engine can find it later;
/// - a read filters `deleted_at IS NULL`, so a soft-deleted row is invisible
///   even though it still has to travel to the server.
///
/// The type is `nonisolated` and `Sendable`: its methods block on a database
/// queue and must be callable from anywhere, including the sync engine.
nonisolated final class GymRepository: Sendable {

    /// Exposed so the sync engine and `ValueObservation.start(in:)` can reach
    /// the same connection; nothing else should query it directly.
    let dbWriter: any DatabaseWriter
    let clock: any AppClock

    init(dbWriter: any DatabaseWriter, clock: any AppClock = SystemClock()) {
        self.dbWriter = dbWriter
        self.clock = clock
    }

    // MARK: - Programs

    /// The program flagged active, or `nil` before the user made one.
    func activeProgram() throws -> Program? {
        try dbWriter.read { db in
            try Self.fetchActiveProgram(db)
        }
    }

    /// All programs, alphabetically, case-insensitive.
    func programs() throws -> [Program] {
        try dbWriter.read { db in
            try Program
                .filter(sql: "deleted_at IS NULL")
                .order(sql: "name COLLATE NOCASE")
                .fetchAll(db)
        }
    }

    /// The days of a program, in `position` order.
    func days(of programId: String) throws -> [ProgramDay] {
        try dbWriter.read { db in
            try Self.fetchDays(db, programId: programId)
        }
    }

    /// The planned exercises of a day, in `position` order.
    func programExercises(of dayId: String) throws -> [ProgramExercise] {
        try dbWriter.read { db in
            try Self.fetchProgramExercises(db, dayId: dayId)
        }
    }

    // MARK: - Exercises

    /// The catalog, optionally narrowed to one muscle group and/or a name
    /// search. Either filter is skipped when its argument is empty.
    ///
    /// `%`, `_` and the escape character itself are escaped in the search
    /// term, so typing "100%" looks for that text instead of matching
    /// everything.
    func exercises(muscleGroup: MuscleGroup? = nil, search: String = "") throws -> [Exercise] {
        let group = muscleGroup?.rawValue
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern: String? = trimmed.isEmpty ? nil : "%\(escaped)%"
        return try dbWriter.read { db in
            try Exercise
                .filter(
                    sql: """
                        deleted_at IS NULL
                        AND (:group IS NULL OR muscle_group = :group)
                        AND (:pattern IS NULL OR name LIKE :pattern ESCAPE '\\')
                        """,
                    arguments: ["group": group, "pattern": pattern])
                .order(sql: "name COLLATE NOCASE")
                .fetchAll(db)
        }
    }

    /// One exercise, or `nil` when it is missing or soft-deleted.
    func exercise(id: String) throws -> Exercise? {
        try dbWriter.read { db in
            try Exercise
                .filter(sql: "id = ? AND deleted_at IS NULL", arguments: [id])
                .fetchOne(db)
        }
    }

    // MARK: - Sessions

    /// The most recent sessions, newest first.
    func sessions(limit: Int = 50) throws -> [WorkoutSession] {
        try dbWriter.read { db in
            try Self.fetchSessions(db, limit: limit)
        }
    }

    /// One session, or `nil` when it is missing or soft-deleted.
    func session(id: String) throws -> WorkoutSession? {
        try dbWriter.read { db in
            try WorkoutSession
                .filter(sql: "id = ? AND deleted_at IS NULL", arguments: [id])
                .fetchOne(db)
        }
    }

    /// The sets of a session, in `position` order.
    func sets(of sessionId: String) throws -> [WorkoutSet] {
        try dbWriter.read { db in
            try Self.fetchSets(db, sessionId: sessionId)
        }
    }

    /// The last set of `exerciseId` the user actually completed: newest
    /// session first and, inside it, the last set of that exercise.
    ///
    /// Drives the "Last time 57.5 × 8" caption and the prefill in
    /// `startSession(from:)`.
    func lastCompletedSet(exerciseId: String) throws -> WorkoutSet? {
        try dbWriter.read { db in
            try Self.fetchLastCompletedSet(db, exerciseId: exerciseId)
        }
    }

    /// The day Today suggests (spec §6): the first day of the active program
    /// whose *name* has not been logged in the last six days. When every day
    /// was logged recently it falls back to the first day, and it returns
    /// `nil` when there is no active program or the program has no days.
    ///
    /// Matching on the name rather than on `program_day_id` means renaming a
    /// program, or rebuilding it from scratch, does not make the rotation
    /// forget what was trained this week.
    func nextUpDay() throws -> ProgramDay? {
        let cutoff = clock.nowMs() - 6 * 24 * 60 * 60 * 1000
        return try dbWriter.read { db in
            guard let program = try Self.fetchActiveProgram(db) else { return nil }
            let untrained = try ProgramDay.fetchOne(
                db,
                sql: """
                    SELECT d.*
                    FROM program_day d
                    WHERE d.program_id = ?
                      AND d.deleted_at IS NULL
                      AND NOT EXISTS (
                        SELECT 1
                        FROM workout_session s
                        JOIN program_day pd ON pd.id = s.program_day_id
                        WHERE s.deleted_at IS NULL
                          AND s.started_at >= ?
                          AND pd.name = d.name
                      )
                    ORDER BY d.position
                    LIMIT 1
                    """,
                arguments: [program.id, cutoff])
            if let untrained {
                return untrained
            }
            return try Self.fetchDays(db, programId: program.id).first
        }
    }

    /// The heaviest completed set per session for one exercise over the last
    /// `weeks` weeks, oldest first — the Progress line chart.
    func bestSetPerSession(exerciseId: String, weeks: Int = 12) throws -> [BestSet] {
        let cutoff = clock.nowMs() - Int64(weeks) * 7 * 24 * 60 * 60 * 1000
        return try dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT ss.started_at AS started_at, MAX(s.weight_kg) AS weight_kg
                    FROM workout_set s
                    JOIN workout_session ss ON ss.id = s.session_id
                    WHERE s.exercise_id = ?
                      AND s.completed = 1
                      AND s.deleted_at IS NULL
                      AND ss.deleted_at IS NULL
                      AND ss.started_at >= ?
                    GROUP BY ss.id
                    ORDER BY ss.started_at
                    """,
                arguments: [exerciseId, cutoff])
            return rows.map { row in
                let startedAt: Int64 = row["started_at"]
                let weightKg: Double = row["weight_kg"]
                return BestSet(sessionStartedAt: startedAt, weightKg: weightKg)
            }
        }
    }

    // MARK: - Sync support

    // These two ignore `deleted_at` on purpose: a tombstone is exactly the
    // kind of row the sync engine still has to push.

    /// How many rows of `table` carry local changes, soft-deleted ones included.
    func dirtyCount(of table: SyncedTable) throws -> Int {
        try dbWriter.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(table.rawValue) WHERE dirty = 1")
            return count ?? 0
        }
    }

    /// The `updated_at` of one row, soft-deleted ones included, or `nil` when
    /// the row is gone. The sync engine compares it with the value it pushed
    /// to decide whether `dirty` may be cleared (spec §5).
    func updatedAt(of table: SyncedTable, id: String) throws -> Int64? {
        try dbWriter.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT updated_at FROM \(table.rawValue) WHERE id = ?",
                arguments: [id])
        }
    }

    // MARK: - Writes

    /// Inserts or updates the exercise, stamping `updated_at` and `dirty`.
    func upsert(_ record: Exercise) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            var stamped = record
            stamped.updatedAt = now
            stamped.dirty = true
            try stamped.save(db)
        }
    }

    /// Inserts or updates the program, stamping `updated_at` and `dirty`.
    func upsert(_ record: Program) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            var stamped = record
            stamped.updatedAt = now
            stamped.dirty = true
            try stamped.save(db)
        }
    }

    /// Inserts or updates the program day, stamping `updated_at` and `dirty`.
    func upsert(_ record: ProgramDay) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            var stamped = record
            stamped.updatedAt = now
            stamped.dirty = true
            try stamped.save(db)
        }
    }

    /// Inserts or updates the planned exercise, stamping `updated_at` and `dirty`.
    func upsert(_ record: ProgramExercise) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            var stamped = record
            stamped.updatedAt = now
            stamped.dirty = true
            try stamped.save(db)
        }
    }

    /// Inserts or updates the session, stamping `updated_at` and `dirty`.
    func upsert(_ record: WorkoutSession) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            var stamped = record
            stamped.updatedAt = now
            stamped.dirty = true
            try stamped.save(db)
        }
    }

    /// Inserts or updates the set, stamping `updated_at` and `dirty`.
    func upsert(_ record: WorkoutSet) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            var stamped = record
            stamped.updatedAt = now
            stamped.dirty = true
            try stamped.save(db)
        }
    }

    /// Soft-deletes one row: sets `deleted_at`, stamps `updated_at` and marks
    /// it dirty so the tombstone reaches the server. An already-deleted row is
    /// left alone, which keeps its original deletion time.
    func softDelete(_ table: SyncedTable, id: String) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    UPDATE \(table.rawValue)
                    SET deleted_at = ?, updated_at = ?, dirty = 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, now, id])
        }
    }

    /// Opens a session and, when `day` is given, creates one `workout_set` per
    /// planned target set.
    ///
    /// Each set is prefilled from the last completed set of that exercise and,
    /// failing that, from the plan target weight and reps (spec §6).
    ///
    /// `position` is one running counter across the **whole session**, not per
    /// exercise: sorting by it groups the sets per exercise in the order the
    /// day plans them, and adding a set later just appends. The Session screen
    /// numbers the rows it draws ("#1", "#2") per exercise group, so `position`
    /// is never shown to the user.
    @discardableResult
    func startSession(from day: ProgramDay?) throws -> WorkoutSession {
        let now = clock.nowMs()
        return try dbWriter.write { db in
            let session = WorkoutSession(
                id: Self.newID(),
                updatedAt: now,
                dirty: true,
                startedAt: now,
                programDayId: day?.id)
            try session.insert(db)

            guard let day else { return session }

            var position = 0
            for planned in try Self.fetchProgramExercises(db, dayId: day.id) {
                let last = try Self.fetchLastCompletedSet(db, exerciseId: planned.exerciseId)
                let weightKg = last?.weightKg ?? planned.targetWeightKg ?? 0
                let reps = last?.reps ?? planned.targetReps
                for _ in 0 ..< max(planned.targetSets, 0) {
                    let set = WorkoutSet(
                        id: Self.newID(),
                        updatedAt: now,
                        dirty: true,
                        sessionId: session.id,
                        exerciseId: planned.exerciseId,
                        position: position,
                        weightKg: weightKg,
                        reps: reps)
                    try set.insert(db)
                    position += 1
                }
            }
            return session
        }
    }

    /// Marks a session finished. A second call re-stamps `finished_at`, which
    /// is harmless and keeps the method idempotent from the point of view of
    /// the UI.
    func finishSession(id: String) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET finished_at = ?, updated_at = ?, dirty = 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, now, id])
        }
    }

    /// Discards a session: soft-deletes it *and* every set that belongs to it,
    /// in one transaction, so the history never keeps orphaned sets and the
    /// sync engine pushes both tombstones together.
    func discardSession(id: String) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_set
                    SET deleted_at = ?, updated_at = ?, dirty = 1
                    WHERE session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, now, id])
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET deleted_at = ?, updated_at = ?, dirty = 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, now, id])
        }
    }

    /// Points an exercise at a freshly uploaded photo, or clears it with `nil`.
    func setImageKey(exerciseId: String, key: String?) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    UPDATE exercise
                    SET image_key = ?, updated_at = ?, dirty = 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [key, now, exerciseId])
        }
    }

    /// Creates a program. The very first one becomes active straight away, so
    /// Today has something to show right after onboarding.
    @discardableResult
    func createProgram(name: String) throws -> Program {
        let now = clock.nowMs()
        return try dbWriter.write { db in
            let activeCount = try Program
                .filter(sql: "is_active = 1 AND deleted_at IS NULL")
                .fetchCount(db)
            let program = Program(
                id: Self.newID(),
                updatedAt: now,
                dirty: true,
                name: name,
                isActive: activeCount == 0)
            try program.insert(db)
            return program
        }
    }

    /// Makes one program active and deactivates the others, in one transaction
    /// so the "at most one active" rule never breaks, not even mid-sync.
    func setActiveProgram(id: String) throws {
        let now = clock.nowMs()
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    UPDATE program
                    SET is_active = 0, updated_at = ?, dirty = 1
                    WHERE is_active = 1 AND id <> ?
                    """,
                arguments: [now, id])
            try db.execute(
                sql: """
                    UPDATE program
                    SET is_active = 1, updated_at = ?, dirty = 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, id])
        }
    }

    // MARK: - Observation

    /// Tracks the history list. Start it with
    /// `observation.start(in: repository.dbWriter, onError:onChange:)`.
    func observeSessions(limit: Int = 50) -> ValueObservation<ValueReducers.Fetch<[WorkoutSession]>> {
        ValueObservation.tracking { db in
            try Self.fetchSessions(db, limit: limit)
        }
    }

    /// Tracks the sets of one session, so the Session screen redraws itself
    /// after every tap on a completion circle.
    func observeSets(of sessionId: String) -> ValueObservation<ValueReducers.Fetch<[WorkoutSet]>> {
        ValueObservation.tracking { db in
            try Self.fetchSets(db, sessionId: sessionId)
        }
    }

    /// Tracks the active program, for Today and the Programs list.
    func observeActiveProgram() -> ValueObservation<ValueReducers.Fetch<Program?>> {
        ValueObservation.tracking { db in
            try Self.fetchActiveProgram(db)
        }
    }

    // MARK: - Shared fetches

    // Static, so the observation closures and the `startSession` transaction
    // can reuse them without capturing `self`.

    private static func fetchActiveProgram(_ db: Database) throws -> Program? {
        // A sync pull can land the new active program before the tombstone of
        // the old flag, leaving two rows with `is_active = 1` for a moment.
        // The most recently updated one is the one the user meant.
        try Program
            .filter(sql: "is_active = 1 AND deleted_at IS NULL")
            .order(sql: "updated_at DESC")
            .fetchOne(db)
    }

    private static func fetchDays(_ db: Database, programId: String) throws -> [ProgramDay] {
        try ProgramDay
            .filter(sql: "program_id = ? AND deleted_at IS NULL", arguments: [programId])
            .order(sql: "position")
            .fetchAll(db)
    }

    private static func fetchProgramExercises(_ db: Database, dayId: String) throws -> [ProgramExercise] {
        try ProgramExercise
            .filter(sql: "program_day_id = ? AND deleted_at IS NULL", arguments: [dayId])
            .order(sql: "position")
            .fetchAll(db)
    }

    private static func fetchSessions(_ db: Database, limit: Int) throws -> [WorkoutSession] {
        try WorkoutSession
            .filter(sql: "deleted_at IS NULL")
            .order(sql: "started_at DESC")
            .limit(limit)
            .fetchAll(db)
    }

    private static func fetchSets(_ db: Database, sessionId: String) throws -> [WorkoutSet] {
        try WorkoutSet
            .filter(sql: "session_id = ? AND deleted_at IS NULL", arguments: [sessionId])
            .order(sql: "position")
            .fetchAll(db)
    }

    private static func fetchLastCompletedSet(_ db: Database, exerciseId: String) throws -> WorkoutSet? {
        try WorkoutSet.fetchOne(
            db,
            sql: """
                SELECT s.*
                FROM workout_set s
                JOIN workout_session ss ON ss.id = s.session_id
                WHERE s.exercise_id = ?
                  AND s.completed = 1
                  AND s.deleted_at IS NULL
                  AND ss.deleted_at IS NULL
                ORDER BY ss.started_at DESC, s.position DESC
                LIMIT 1
                """,
            arguments: [exerciseId])
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }
}
