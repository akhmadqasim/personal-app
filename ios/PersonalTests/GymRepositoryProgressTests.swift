import Testing

@testable import Personal

/// One day and one week in milliseconds — the unit every timestamp column uses.
private let dayMs: Int64 = 24 * 60 * 60 * 1000
private let hourMs: Int64 = 60 * 60 * 1000
private let weekMs: Int64 = 7 * dayMs

/// Monday 2023-09-04T00:00:00Z. Deliberately a week boundary: the volume
/// buckets are Monday-aligned, so an anchor on a Monday makes every expected
/// `weekStartMs` a plain multiple of `weekMs` away from it.
private let mondayBase: Int64 = 1_693_785_600_000

/// "Now" for the progress fixture — four and a bit weeks after the anchor, so
/// the 12-week window comfortably covers every seeded session.
private let progressNow: Int64 = mondayBase + 4 * weekMs + 3 * dayMs

private func makeProgressRepository() throws -> (GymRepository, FixedClock) {
    let clock = FixedClock(progressNow)
    let database = try AppDatabase.inMemory()
    return (GymRepository(dbWriter: database, clock: clock), clock)
}

/// Three sessions of bench press, one of a barbell row, one untouched
/// exercise, and one bench session far outside the 12-week window.
///
/// Bench press per week: 50 × 10 + 60 × 8 = 980, then 62.5 × 8 = 500 (the
/// 70 × 5 was never ticked off), then 65 × 8 = 520 (the 40 × 10 was deleted).
/// Total 2000 against the row's 100, so bench press leads the chips.
private func seedProgressFixture(_ repository: GymRepository) throws {
    try repository.upsert(
        Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
    try repository.upsert(
        Exercise(id: "e2", name: "Barbell row", muscleGroup: .back, equipment: .barbell))
    try repository.upsert(
        Exercise(id: "e3", name: "Plank", muscleGroup: .core, equipment: .bodyweight))

    // Week 0.
    try repository.upsert(WorkoutSession(id: "s1", startedAt: mondayBase + dayMs))
    try repository.upsert(
        WorkoutSet(
            id: "a1", sessionId: "s1", exerciseId: "e1",
            position: 0, weightKg: 50, reps: 10, completed: true))
    try repository.upsert(
        WorkoutSet(
            id: "a2", sessionId: "s1", exerciseId: "e1",
            position: 1, weightKg: 60, reps: 8, completed: true))

    // Week 1 — the second set was planned but never completed.
    try repository.upsert(WorkoutSession(id: "s2", startedAt: mondayBase + weekMs + 2 * dayMs))
    try repository.upsert(
        WorkoutSet(
            id: "b1", sessionId: "s2", exerciseId: "e1",
            position: 0, weightKg: 62.5, reps: 8, completed: true))
    try repository.upsert(
        WorkoutSet(
            id: "b2", sessionId: "s2", exerciseId: "e1",
            position: 1, weightKg: 70, reps: 5))

    // Week 2 — the second set was completed and then deleted.
    try repository.upsert(WorkoutSession(id: "s3", startedAt: mondayBase + 2 * weekMs + dayMs))
    try repository.upsert(
        WorkoutSet(
            id: "c1", sessionId: "s3", exerciseId: "e1",
            position: 0, weightKg: 65, reps: 8, completed: true))
    try repository.upsert(
        WorkoutSet(
            id: "c2", sessionId: "s3", exerciseId: "e1",
            position: 1, weightKg: 40, reps: 10, completed: true))
    try repository.softDelete(.workoutSet, id: "c2")

    // A different exercise, same week, far less volume.
    try repository.upsert(WorkoutSession(id: "s4", startedAt: mondayBase + 2 * weekMs + 2 * dayMs))
    try repository.upsert(
        WorkoutSet(
            id: "d1", sessionId: "s4", exerciseId: "e2",
            position: 0, weightKg: 100, reps: 1, completed: true))

    // Sixteen weeks before the anchor: outside a 12-week window, inside a
    // 52-week one.
    try repository.upsert(WorkoutSession(id: "s5", startedAt: progressNow - 20 * weekMs))
    try repository.upsert(
        WorkoutSet(
            id: "e_old", sessionId: "s5", exerciseId: "e1",
            position: 0, weightKg: 200, reps: 10, completed: true))
}

struct GymRepositoryProgressTests {

    // MARK: - Weekly volume

    @Test func weeklyVolumeSumsCompletedSetsPerWeek() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let weeks = try repository.weeklyVolume(exerciseId: "e1", weeks: 12)

        #expect(weeks.count == 3)
        #expect(weeks[0].weekStartMs == mondayBase)
        #expect(weeks[0].volumeKg == 980)
        #expect(weeks[1].weekStartMs == mondayBase + weekMs)
        // The 70 × 5 of that session was never ticked off.
        #expect(weeks[1].volumeKg == 500)
        #expect(weeks[2].weekStartMs == mondayBase + 2 * weekMs)
        // The 40 × 10 of that session was soft-deleted.
        #expect(weeks[2].volumeKg == 520)
    }

    @Test func weeklyVolumeCountsOnlyTheExerciseItWasAskedFor() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let weeks = try repository.weeklyVolume(exerciseId: "e2", weeks: 12)

        #expect(weeks.count == 1)
        #expect(weeks[0].weekStartMs == mondayBase + 2 * weekMs)
        #expect(weeks[0].volumeKg == 100)
    }

    @Test func weeklyVolumeBucketsStartOnMonday() throws {
        let (repository, _) = try makeProgressRepository()
        try repository.upsert(
            Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
        // Sunday 23:00 of one week, then the Monday midnight that opens the next.
        try repository.upsert(WorkoutSession(id: "sa", startedAt: mondayBase + 6 * dayMs + 23 * hourMs))
        try repository.upsert(WorkoutSession(id: "sb", startedAt: mondayBase + weekMs))
        try repository.upsert(
            WorkoutSet(
                id: "xa", sessionId: "sa", exerciseId: "e1",
                position: 0, weightKg: 10, reps: 1, completed: true))
        try repository.upsert(
            WorkoutSet(
                id: "xb", sessionId: "sb", exerciseId: "e1",
                position: 0, weightKg: 20, reps: 1, completed: true))

        let weeks = try repository.weeklyVolume(exerciseId: "e1", weeks: 12)

        #expect(weeks.count == 2)
        #expect(weeks[0].weekStartMs == mondayBase)
        #expect(weeks[0].volumeKg == 10)
        #expect(weeks[1].weekStartMs == mondayBase + weekMs)
        #expect(weeks[1].volumeKg == 20)
    }

    @Test func weeklyVolumeStopsAtTheWindow() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let narrow = try repository.weeklyVolume(exerciseId: "e1", weeks: 12)
        #expect(narrow.count == 3)

        // A year-wide window picks the old session up as a fourth, earlier week.
        let wide = try repository.weeklyVolume(exerciseId: "e1", weeks: 52)
        #expect(wide.count == 4)
        #expect(wide[0].volumeKg == 2_000)
        #expect(wide[0].weekStartMs < mondayBase)
    }

    // MARK: - Top exercises

    @Test func topExercisesAreOrderedByRecentVolume() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let top = try repository.topExercisesByVolume(limit: 6, weeks: 12)

        // "Plank" has no set at all, so it is not in there.
        #expect(top.count == 2)
        #expect(top[0].id == "e1")
        #expect(top[1].id == "e2")
    }

    @Test func topExercisesRespectTheLimit() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let top = try repository.topExercisesByVolume(limit: 1, weeks: 12)

        #expect(top.count == 1)
        #expect(top[0].id == "e1")
    }

    @Test func withoutACompletedSetNoExerciseIsListed() throws {
        let (repository, _) = try makeProgressRepository()
        try repository.upsert(
            Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
        try repository.upsert(WorkoutSession(id: "s1", startedAt: mondayBase + dayMs))
        // Logged but never ticked off.
        try repository.upsert(
            WorkoutSet(
                id: "a1", sessionId: "s1", exerciseId: "e1",
                position: 0, weightKg: 50, reps: 10))

        let top = try repository.topExercisesByVolume(limit: 6, weeks: 12)

        #expect(top.isEmpty)
    }

    // MARK: - Personal best

    @Test func personalBestIsTheHeaviestCompletedSetInTheWindow() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let record = try repository.personalBest(exerciseId: "e1", weeks: 12)
        let best = try #require(record)

        #expect(best.weightKg == 65)
        #expect(best.reps == 8)
        #expect(best.sessionStartedAt == mondayBase + 2 * weekMs + dayMs)
    }

    @Test func personalBestWidensWithTheWindow() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let record = try repository.personalBest(exerciseId: "e1", weeks: 52)
        let best = try #require(record)

        #expect(best.weightKg == 200)
        #expect(best.reps == 10)
    }

    @Test func withoutACompletedSetThereIsNoPersonalBest() throws {
        let (repository, _) = try makeProgressRepository()
        try seedProgressFixture(repository)

        let record = try repository.personalBest(exerciseId: "e3", weeks: 12)

        #expect(record == nil)
    }
}
