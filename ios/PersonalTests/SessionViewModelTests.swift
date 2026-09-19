import Testing

@testable import Personal

private let sessionBase: Int64 = 1_700_000_000_000

private func makeSessionFixture(now: Int64 = sessionBase) throws -> (GymRepository, FixedClock) {
    let clock = FixedClock(now)
    let database = try AppDatabase.inMemory()
    return (GymRepository(dbWriter: database, clock: clock), clock)
}

/// One active program day planning two sets of one exercise, so a started
/// session has exactly two rows to work with.
private func seedSessionProgram(_ repository: GymRepository) throws {
    try repository.upsert(
        Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
    try repository.upsert(Program(id: "p1", name: "Push Pull Legs"))
    try repository.setActiveProgram(id: "p1")
    try repository.upsert(ProgramDay(id: "d0", programId: "p1", name: "Push A", position: 0))
    try repository.upsert(
        ProgramExercise(
            id: "pe0",
            programDayId: "d0",
            exerciseId: "e1",
            position: 0,
            targetSets: 2,
            targetReps: 8,
            targetWeightKg: 60))
}

/// Seeds, starts a session on the suggested day and hands back a loaded view
/// model. The view model runs without a scheduler or an image store: neither
/// has anything to say about the behaviour under test.
private func makeLoadedSession(
    _ repository: GymRepository
) throws -> (SessionViewModel, WorkoutSession) {
    let day = try repository.nextUpDay()
    let session = try repository.startSession(from: day)
    let model = SessionViewModel(sessionId: session.id, repository: repository)
    model.loadSession()
    return (model, session)
}

@MainActor
struct SessionViewModelTests {

    // MARK: - Loading

    @Test func theSessionTakesItsTitleFromTheProgramDay() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)

        let (model, _) = try makeLoadedSession(repository)

        #expect(model.title == "Push A")
        #expect(model.groups.count == 1)
        let group = try #require(model.groups.first)
        #expect(group.name == "Bench press")
        #expect(group.muscleLabel == "Chest")
        // Nothing was ever completed, so there is no "last time" caption yet.
        #expect(group.lastTime == nil)
    }

    @Test func setsAreRenumberedPerExercise() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)

        let (model, _) = try makeLoadedSession(repository)

        let group = try #require(model.groups.first)
        #expect(group.sets.count == 2)
        #expect(group.sets[0].number == 1)
        #expect(group.sets[1].number == 2)
        #expect(group.sets[0].valueText == "60 kg × 8")
    }

    // MARK: - Completing

    @Test func completingASetFlipsTheColumn() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        let row = try #require(group.sets.first)
        #expect(row.completed == false)

        model.toggleCompleted(row.id)

        let stored = try repository.sets(of: session.id)
        let match = stored.first(where: { $0.id == row.id })
        let updated = try #require(match)
        #expect(updated.completed == true)

        let rebuilt = try #require(model.groups.first)
        #expect(rebuilt.sets[0].completed == true)
    }

    @Test func completingASetIsUndoneByASecondTap() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        let row = try #require(group.sets.first)

        model.toggleCompleted(row.id)
        model.toggleCompleted(row.id)

        let stored = try repository.sets(of: session.id)
        let match = stored.first(where: { $0.id == row.id })
        let updated = try #require(match)
        #expect(updated.completed == false)
    }

    /// The regression that made "Last time" erase itself: once the first set
    /// of the running session was ticked off it became *the* last completed
    /// set, and the caption echoed it back instead of last week's numbers.
    @Test func theLastTimeCaptionIgnoresThisSessionsOwnSets() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        // Last week: bench pressed at 45 × 12.
        try repository.upsert(
            WorkoutSession(id: "s0", startedAt: sessionBase - 1_000, finishedAt: sessionBase - 500))
        try repository.upsert(
            WorkoutSet(
                id: "old",
                sessionId: "s0",
                exerciseId: "e1",
                position: 0,
                weightKg: 45,
                reps: 12,
                completed: true))

        let (model, session) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        #expect(group.lastTime == "Last time 45 × 12")
        let row = try #require(group.sets.first)

        // Today: a heavier, shorter set, ticked off.
        model.updateSet(row.id, weightKg: 50, reps: 5, rpe: nil)
        model.toggleCompleted(row.id)

        let live = try #require(model.groups.first)
        #expect(live.lastTime == "Last time 45 × 12")

        // A second view model reads it fresh, so the caption is right because
        // of the query, not because of the cache.
        let reopened = SessionViewModel(sessionId: session.id, repository: repository)
        reopened.loadSession()
        let rebuilt = try #require(reopened.groups.first)
        #expect(rebuilt.lastTime == "Last time 45 × 12")
    }

    // MARK: - Adding and editing

    @Test func addingASetCopiesTheOneBefore() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, _) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        let previous = try #require(group.sets.last)

        model.addSet(to: group.id)

        let rebuilt = try #require(model.groups.first)
        #expect(rebuilt.sets.count == 3)
        let added = try #require(rebuilt.sets.last)
        #expect(added.weightKg == previous.weightKg)
        #expect(added.reps == previous.reps)
        #expect(added.completed == false)
        #expect(added.number == 3)
    }

    @Test func addingASetCopiesTheRPETheUserWasWorkingAt() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, _) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        let last = try #require(group.sets.last)
        model.updateSet(last.id, weightKg: 62.5, reps: 6, rpe: 8.5)

        model.addSet(to: group.id)

        let rebuilt = try #require(model.groups.first)
        let added = try #require(rebuilt.sets.last)
        #expect(added.weightKg == 62.5)
        #expect(added.reps == 6)
        #expect(added.rpe == 8.5)
    }

    @Test func editingASetClampsRepsAndWeight() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        let row = try #require(group.sets.first)

        model.updateSet(row.id, weightKg: -5, reps: 0, rpe: 12)

        let stored = try repository.sets(of: session.id)
        let match = stored.first(where: { $0.id == row.id })
        let updated = try #require(match)
        #expect(updated.weightKg == 0)
        #expect(updated.reps == 1)
        #expect(updated.rpe == 10.0)
    }

    @Test func deletingASetHidesItWithoutLosingTheTombstone() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)
        let group = try #require(model.groups.first)
        let row = try #require(group.sets.first)

        model.deleteSet(row.id)

        let stored = try repository.sets(of: session.id)
        #expect(stored.count == 1)
        let rebuilt = try #require(model.groups.first)
        #expect(rebuilt.sets.count == 1)
        // The row is still there for the sync engine to push.
        let dirty = try repository.dirtyCount(of: .workoutSet)
        #expect(dirty == 2)
    }

    @Test func addingAnExerciseStartsItFromTheLastCompletedSet() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        try repository.upsert(
            Exercise(id: "e2", name: "Lat pulldown", muscleGroup: .back, equipment: .cable))
        // An older, finished session where the movement was completed at 45 × 12.
        try repository.upsert(
            WorkoutSession(id: "s0", startedAt: sessionBase - 1_000, finishedAt: sessionBase - 500))
        try repository.upsert(
            WorkoutSet(
                id: "old",
                sessionId: "s0",
                exerciseId: "e2",
                position: 0,
                weightKg: 45,
                reps: 12,
                completed: true))
        let (model, _) = try makeLoadedSession(repository)
        let exercise = try repository.exercise(id: "e2")
        let picked = try #require(exercise)

        model.addExercise(picked)

        #expect(model.groups.count == 2)
        let added = try #require(model.groups.last)
        #expect(added.name == "Lat pulldown")
        #expect(added.lastTime == "Last time 45 × 12")
        let row = try #require(added.sets.first)
        #expect(row.weightKg == 45)
        #expect(row.reps == 12)
        #expect(row.number == 1)
    }

    // MARK: - Finishing and discarding

    @Test func finishingStampsFinishedAt() throws {
        let (repository, clock) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)
        clock.set(sessionBase + 3_600_000)

        model.finish()

        let stored = try repository.session(id: session.id)
        let finished = try #require(stored)
        #expect(finished.finishedAt == sessionBase + 3_600_000)
        #expect(model.isFinished == true)
    }

    @Test func discardingSoftDeletesTheSessionAndItsSets() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)

        model.discard()

        let stored = try repository.session(id: session.id)
        #expect(stored == nil)
        let sets = try repository.sets(of: session.id)
        #expect(sets.isEmpty)
        #expect(model.isGone == true)
    }

    @Test func renamingOverridesTheDayName() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, session) = try makeLoadedSession(repository)

        model.renameText = "  Deload  "
        model.commitRename()

        #expect(model.title == "Deload")
        let stored = try repository.session(id: session.id)
        let renamed = try #require(stored)
        #expect(renamed.notes == "Deload")
    }

    @Test func clearingTheRenameFallsBackToTheDayName() throws {
        let (repository, _) = try makeSessionFixture()
        try seedSessionProgram(repository)
        let (model, _) = try makeLoadedSession(repository)
        model.renameText = "Deload"
        model.commitRename()

        model.renameText = "   "
        model.commitRename()

        #expect(model.title == "Push A")
    }
}
