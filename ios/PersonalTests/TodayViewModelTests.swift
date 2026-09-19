import Testing

@testable import Personal

/// An arbitrary but fixed "now" — the same anchor `GymRepositoryTests` uses.
private let todayBase: Int64 = 1_700_000_000_000

private func makeTodayFixture(now: Int64 = todayBase) throws -> (GymRepository, FixedClock) {
    let clock = FixedClock(now)
    let database = try AppDatabase.inMemory()
    return (GymRepository(dbWriter: database, clock: clock), clock)
}

/// One active program, one day, two planned exercises of two sets each and no
/// rest override — so the estimate is 2 × 2 × (90 + 40) s = 520 s = 8 min.
private func seedTodayProgram(_ repository: GymRepository) throws {
    try repository.upsert(
        Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
    try repository.upsert(
        Exercise(id: "e2", name: "Overhead press", muscleGroup: .shoulders, equipment: .barbell))
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
    try repository.upsert(
        ProgramExercise(
            id: "pe1",
            programDayId: "d0",
            exerciseId: "e2",
            position: 1,
            targetSets: 2,
            targetReps: 10,
            targetWeightKg: 40))
}

@MainActor
struct TodayViewModelTests {

    // MARK: - Empty

    @Test func withoutAnActiveProgramTodayHasNothingToSuggest() throws {
        let (repository, _) = try makeTodayFixture()
        let model = TodayViewModel(repository: repository)

        model.reload()

        #expect(model.state == .noProgram)
        #expect(model.nextUp == nil)
        #expect(model.history.isEmpty)
    }

    // MARK: - Next up

    @Test func nextUpSummarisesTheSuggestedDay() throws {
        let (repository, _) = try makeTodayFixture()
        try seedTodayProgram(repository)
        let model = TodayViewModel(repository: repository)

        model.reload()

        #expect(model.state == .ready)
        let nextUp = try #require(model.nextUp)
        #expect(nextUp.day.name == "Push A")
        #expect(nextUp.exerciseCount == 2)
        #expect(nextUp.estimatedMinutes == 8)
        #expect(nextUp.meta == "2 exercises · ~8 min")
    }

    @Test func theRestOverrideChangesTheEstimate() throws {
        let (repository, _) = try makeTodayFixture()
        try seedTodayProgram(repository)
        // 2 × 2 × (160 + 40) s = 800 s = 13 min.
        try repository.upsert(
            ProgramExercise(
                id: "pe0",
                programDayId: "d0",
                exerciseId: "e1",
                position: 0,
                targetSets: 2,
                targetReps: 8,
                targetWeightKg: 60,
                restSeconds: 160))
        try repository.upsert(
            ProgramExercise(
                id: "pe1",
                programDayId: "d0",
                exerciseId: "e2",
                position: 1,
                targetSets: 2,
                targetReps: 10,
                targetWeightKg: 40,
                restSeconds: 160))
        let model = TodayViewModel(repository: repository)

        model.reload()

        let nextUp = try #require(model.nextUp)
        #expect(nextUp.estimatedMinutes == 13)
    }

    @Test func aProgramWithoutDaysHasNoCard() throws {
        let (repository, _) = try makeTodayFixture()
        try repository.upsert(Program(id: "p1", name: "Empty"))
        try repository.setActiveProgram(id: "p1")
        let model = TodayViewModel(repository: repository)

        model.reload()

        #expect(model.state == .ready)
        #expect(model.nextUp == nil)
    }

    // MARK: - Starting a session

    @Test func startingASessionCreatesItAndItsSets() throws {
        let (repository, _) = try makeTodayFixture()
        try seedTodayProgram(repository)
        let model = TodayViewModel(repository: repository)
        model.reload()

        let sessionId = try #require(model.startSession())

        let stored = try repository.session(id: sessionId)
        let session = try #require(stored)
        #expect(session.programDayId == "d0")
        #expect(session.finishedAt == nil)

        // Two planned exercises of two target sets each.
        let sets = try repository.sets(of: sessionId)
        #expect(sets.count == 4)
        #expect(sets[0].exerciseId == "e1")
        #expect(sets[3].exerciseId == "e2")
        // Prefilled from the plan, since nothing was ever completed.
        #expect(sets[0].weightKg == 60)
        #expect(sets[0].reps == 8)
        #expect(sets[0].completed == false)
    }

    @Test func aStartedSessionShowsUpInTheHistory() throws {
        let (repository, _) = try makeTodayFixture()
        try seedTodayProgram(repository)
        let model = TodayViewModel(repository: repository)
        model.reload()

        model.startSession()

        #expect(model.history.count == 1)
        let group = try #require(model.history.first)
        #expect(group.items.count == 1)
        let item = try #require(group.items.first)
        #expect(item.title == "Push A")
        #expect(item.isFinished == false)
        #expect(item.setsText == "0/4 sets")
        #expect(item.durationText == nil)
    }
}
