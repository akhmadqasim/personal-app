import Testing

@testable import Personal

/// One day in milliseconds — the unit every timestamp column uses.
private let oneDay: Int64 = 24 * 60 * 60 * 1000

/// An arbitrary but fixed "now" the tests move around with `FixedClock`.
private let base: Int64 = 1_700_000_000_000

private func makeRepository(now: Int64 = base) throws -> (GymRepository, FixedClock) {
    let clock = FixedClock(now)
    let database = try AppDatabase.inMemory()
    return (GymRepository(dbWriter: database, clock: clock), clock)
}

/// Seeds one exercise, one active program and a day per name, each day
/// planning the same exercise. Ids are predictable: `e1`, `p1`, `d0`, `d1`, …
private func seedProgram(
    _ repository: GymRepository,
    dayNames: [String],
    targetSets: Int = 3,
    targetReps: Int = 8,
    targetWeightKg: Double? = 50
) throws {
    try repository.upsert(
        Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
    try repository.upsert(Program(id: "p1", name: "Push Pull Legs"))
    try repository.setActiveProgram(id: "p1")

    for (index, name) in dayNames.enumerated() {
        try repository.upsert(
            ProgramDay(id: "d\(index)", programId: "p1", name: name, position: index))
        try repository.upsert(
            ProgramExercise(
                id: "pe\(index)",
                programDayId: "d\(index)",
                exerciseId: "e1",
                position: 0,
                targetSets: targetSets,
                targetReps: targetReps,
                targetWeightKg: targetWeightKg))
    }
}

struct GymRepositoryTests {

    // MARK: - Write stamping

    @Test func everyWriteStampsUpdatedAtAndDirty() throws {
        let (repository, clock) = try makeRepository(now: 1_000)

        // The caller's own `updatedAt` / `dirty` are overwritten on purpose:
        // the repository owns those two columns.
        try repository.upsert(
            Exercise(
                id: "e1", updatedAt: 42, dirty: false,
                name: "Bench press", muscleGroup: .chest, equipment: .barbell))

        let stored = try repository.exercise(id: "e1")
        #expect(stored?.updatedAt == 1_000)
        #expect(stored?.dirty == true)

        clock.set(2_000)
        var edit = try #require(stored)
        edit.name = "Incline bench press"
        edit.dirty = false
        try repository.upsert(edit)

        let updated = try repository.exercise(id: "e1")
        #expect(updated?.updatedAt == 2_000)
        #expect(updated?.name == "Incline bench press")
        #expect(updated?.dirty == true)
    }

    @Test func finishSessionStampsFinishedAtAndDirty() throws {
        let (repository, clock) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"])
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)

        let session = try repository.startSession(from: day)
        #expect(session.finishedAt == nil)

        clock.set(base + 3_600_000)
        try repository.finishSession(id: session.id)

        let finished = try repository.session(id: session.id)
        #expect(finished?.finishedAt == base + 3_600_000)
        #expect(finished?.updatedAt == base + 3_600_000)
        #expect(finished?.dirty == true)
        #expect(finished?.isFinished == true)
    }

    @Test func setImageKeyStampsTheExercise() throws {
        let (repository, clock) = try makeRepository(now: 1_000)
        try repository.upsert(
            Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))

        clock.set(5_000)
        try repository.setImageKey(exerciseId: "e1", key: "img/abc.jpg")

        let stored = try repository.exercise(id: "e1")
        #expect(stored?.imageKey == "img/abc.jpg")
        #expect(stored?.updatedAt == 5_000)
        #expect(stored?.dirty == true)
    }

    // MARK: - Soft delete

    @Test func softDeletedRowsAreInvisibleToReads() throws {
        let (repository, clock) = try makeRepository(now: 1_000)
        try repository.upsert(
            Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
        try repository.upsert(
            Exercise(id: "e2", name: "Row", muscleGroup: .back, equipment: .cable))

        clock.set(2_000)
        try repository.softDelete(.exercise, id: "e1")

        let single = try repository.exercise(id: "e1")
        #expect(single == nil)

        let remaining = try repository.exercises()
        #expect(remaining.map(\.id) == ["e2"])

        // The tombstone stays behind, stamped and dirty, so sync can push it.
        let tombstoneUpdatedAt = try repository.updatedAt(of: .exercise, id: "e1")
        #expect(tombstoneUpdatedAt == 2_000)
        let dirty = try repository.dirtyCount(of: .exercise)
        #expect(dirty == 2)
    }

    @Test func softDeletedSessionsDisappearFromHistory() throws {
        let (repository, _) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"])
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)
        let session = try repository.startSession(from: day)

        try repository.softDelete(.workoutSession, id: session.id)

        let history = try repository.sessions()
        #expect(history.isEmpty)
        let fetched = try repository.session(id: session.id)
        #expect(fetched == nil)
    }

    @Test func discardSessionAlsoSoftDeletesItsSets() throws {
        let (repository, clock) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"], targetSets: 3)
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)
        let session = try repository.startSession(from: day)

        let before = try repository.sets(of: session.id)
        #expect(before.count == 3)

        clock.set(base + 5_000)
        try repository.discardSession(id: session.id)

        let after = try repository.sets(of: session.id)
        #expect(after.isEmpty)
        let fetched = try repository.session(id: session.id)
        #expect(fetched == nil)

        // Session and sets are stamped with the same instant and stay dirty,
        // so both tombstones travel in the next push.
        let sessionUpdatedAt = try repository.updatedAt(of: .workoutSession, id: session.id)
        #expect(sessionUpdatedAt == base + 5_000)
        let setUpdatedAt = try repository.updatedAt(of: .workoutSet, id: before[0].id)
        #expect(setUpdatedAt == base + 5_000)
        let dirtySets = try repository.dirtyCount(of: .workoutSet)
        #expect(dirtySets == 3)
        let dirtySessions = try repository.dirtyCount(of: .workoutSession)
        #expect(dirtySessions == 1)
    }

    // MARK: - Starting a session

    @Test func startSessionPrefillsFromTheTargetsWithoutHistory() throws {
        let (repository, _) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"], targetSets: 3, targetReps: 8, targetWeightKg: 50)
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)

        let session = try repository.startSession(from: day)
        let sets = try repository.sets(of: session.id)

        #expect(session.programDayId == "d0")
        #expect(session.startedAt == base)
        #expect(session.dirty == true)
        #expect(sets.count == 3)
        #expect(sets.map(\.position) == [0, 1, 2])
        // One expectation per field: a closure with several comparisons inside
        // `#expect` expands into an expression the type checker gives up on.
        for set in sets {
            #expect(set.weightKg == 50)
            #expect(set.reps == 8)
            #expect(set.completed == false)
        }
    }

    @Test func startSessionPrefillsFromTheLastCompletedSet() throws {
        let (repository, clock) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"], targetSets: 3, targetReps: 8, targetWeightKg: 50)
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)

        let first = try repository.startSession(from: day)
        let firstSets = try repository.sets(of: first.id)
        var lastSet = try #require(firstSets.last)
        lastSet.weightKg = 57.5
        lastSet.reps = 6
        lastSet.completed = true
        try repository.upsert(lastSet)

        clock.advance(by: oneDay)
        let second = try repository.startSession(from: day)
        let sets = try repository.sets(of: second.id)

        #expect(sets.count == 3)
        for set in sets {
            #expect(set.weightKg == 57.5)
            #expect(set.reps == 6)
        }
    }

    @Test func startSessionWithoutADayCreatesAFreeSession() throws {
        let (repository, _) = try makeRepository()
        let session = try repository.startSession(from: nil)

        #expect(session.programDayId == nil)
        let sets = try repository.sets(of: session.id)
        #expect(sets.isEmpty)
    }

    @Test func lastCompletedSetIgnoresUnfinishedAndDeletedWork() throws {
        let (repository, _) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"])
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)
        let session = try repository.startSession(from: day)

        // Nothing completed yet.
        let none = try repository.lastCompletedSet(exerciseId: "e1")
        #expect(none == nil)

        let plannedSets = try repository.sets(of: session.id)
        var set = try #require(plannedSets.first)
        set.completed = true
        set.weightKg = 62.5
        try repository.upsert(set)

        let found = try repository.lastCompletedSet(exerciseId: "e1")
        #expect(found?.weightKg == 62.5)

        // Deleting the session hides its sets from history too.
        try repository.softDelete(.workoutSession, id: session.id)
        let afterDelete = try repository.lastCompletedSet(exerciseId: "e1")
        #expect(afterDelete == nil)
    }

    // MARK: - Next up

    @Test func nextUpDaySkipsDaysLoggedInTheLastSixDays() throws {
        let (repository, clock) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A", "Pull B", "Legs C"])
        let days = try repository.days(of: "p1")
        #expect(days.map(\.name) == ["Push A", "Pull B", "Legs C"])

        let untouched = try repository.nextUpDay()
        #expect(untouched?.name == "Push A")

        clock.set(base - 2 * oneDay)
        try repository.startSession(from: days[0])
        clock.set(base)
        let afterPush = try repository.nextUpDay()
        #expect(afterPush?.name == "Pull B")

        clock.set(base - oneDay)
        try repository.startSession(from: days[1])
        clock.set(base)
        let afterPull = try repository.nextUpDay()
        #expect(afterPull?.name == "Legs C")

        // Older than six days: it does not hold a day back any more.
        clock.set(base - 8 * oneDay)
        try repository.startSession(from: days[2])
        clock.set(base)
        let afterOldLegs = try repository.nextUpDay()
        #expect(afterOldLegs?.name == "Legs C")
    }

    @Test func nextUpDayFallsBackToTheFirstDayWhenEverythingWasLogged() throws {
        let (repository, clock) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A", "Pull B", "Legs C"])
        let days = try repository.days(of: "p1")

        clock.set(base - oneDay)
        for day in days {
            try repository.startSession(from: day)
        }
        clock.set(base)

        let suggestion = try repository.nextUpDay()
        #expect(suggestion?.name == "Push A")
    }

    @Test func nextUpDayIsNilWithoutAnActiveProgram() throws {
        let (repository, _) = try makeRepository()
        let suggestion = try repository.nextUpDay()
        #expect(suggestion == nil)
    }

    // MARK: - Programs

    @Test func theFirstProgramBecomesActive() throws {
        let (repository, _) = try makeRepository()

        let first = try repository.createProgram(name: "Push Pull Legs")
        #expect(first.isActive == true)
        #expect(first.dirty == true)
        #expect(first.updatedAt == base)

        let second = try repository.createProgram(name: "Upper Lower")
        #expect(second.isActive == false)

        let active = try repository.activeProgram()
        #expect(active?.id == first.id)
    }

    @Test func setActiveProgramMovesTheFlag() throws {
        let (repository, clock) = try makeRepository()
        let first = try repository.createProgram(name: "Push Pull Legs")
        let second = try repository.createProgram(name: "Upper Lower")

        clock.set(base + 1_000)
        try repository.setActiveProgram(id: second.id)

        let active = try repository.activeProgram()
        #expect(active?.id == second.id)
        #expect(active?.updatedAt == base + 1_000)
        #expect(active?.dirty == true)

        let all = try repository.programs()
        #expect(all.count == 2)
        let activeCount = all.filter(\.isActive).count
        #expect(activeCount == 1)
        let previous = all.first(where: { $0.id == first.id })
        #expect(previous?.isActive == false)
    }

    // MARK: - Catalog filters

    @Test func exercisesFilterByMuscleGroupAndSearch() throws {
        let (repository, _) = try makeRepository()
        try repository.upsert(
            Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
        try repository.upsert(
            Exercise(id: "e2", name: "Incline dumbbell press", muscleGroup: .chest, equipment: .dumbbell))
        try repository.upsert(
            Exercise(id: "e3", name: "Barbell row", muscleGroup: .back, equipment: .barbell))

        let all = try repository.exercises()
        #expect(all.map(\.id) == ["e3", "e1", "e2"])

        let chest = try repository.exercises(muscleGroup: .chest)
        #expect(chest.map(\.id) == ["e1", "e2"])

        let searched = try repository.exercises(search: "press")
        #expect(searched.map(\.id) == ["e1", "e2"])

        let both = try repository.exercises(muscleGroup: .back, search: "row")
        #expect(both.map(\.id) == ["e3"])

        let blankSearchIsIgnored = try repository.exercises(search: "   ")
        #expect(blankSearchIsIgnored.count == 3)
    }

    @Test func searchTreatsLikeWildcardsAsLiteralText() throws {
        let (repository, _) = try makeRepository()
        try repository.upsert(
            Exercise(id: "e1", name: "Bench 100% press", muscleGroup: .chest, equipment: .barbell))
        try repository.upsert(
            Exercise(id: "e2", name: "Barbell row", muscleGroup: .back, equipment: .barbell))

        let percent = try repository.exercises(search: "100%")
        #expect(percent.map(\.id) == ["e1"])

        // "%press" is a literal substring, not "anything then press".
        let notAWildcard = try repository.exercises(search: "%press")
        #expect(notAWildcard.isEmpty)

        let underscore = try repository.exercises(search: "_")
        #expect(underscore.isEmpty)
    }

    // MARK: - Progress

    @Test func bestSetPerSessionKeepsTheHeaviestCompletedSetPerSession() throws {
        let (repository, clock) = try makeRepository()
        try seedProgram(repository, dayNames: ["Push A"], targetSets: 2, targetReps: 8, targetWeightKg: 40)
        let days = try repository.days(of: "p1")
        let day = try #require(days.first)

        clock.set(base - 3 * oneDay)
        let first = try repository.startSession(from: day)
        var firstSets = try repository.sets(of: first.id)
        firstSets[0].weightKg = 40
        firstSets[0].completed = true
        firstSets[1].weightKg = 60
        firstSets[1].completed = true
        try repository.upsert(firstSets[0])
        try repository.upsert(firstSets[1])

        clock.set(base - oneDay)
        let second = try repository.startSession(from: day)
        var secondSets = try repository.sets(of: second.id)
        secondSets[0].weightKg = 55
        secondSets[0].completed = true
        try repository.upsert(secondSets[0])

        clock.set(base)
        let points = try repository.bestSetPerSession(exerciseId: "e1", weeks: 12)

        #expect(points.count == 2)
        #expect(points[0].sessionStartedAt == base - 3 * oneDay)
        #expect(points[0].weightKg == 60)
        #expect(points[1].sessionStartedAt == base - oneDay)
        #expect(points[1].weightKg == 55)

        // Outside the window nothing is left.
        let narrow = try repository.bestSetPerSession(exerciseId: "e1", weeks: 0)
        #expect(narrow.isEmpty)
    }
}
