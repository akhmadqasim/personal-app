import Foundation
import Testing

@testable import Personal

private let progressDayMs: Int64 = 24 * 60 * 60 * 1000
private let progressWeekMs: Int64 = 7 * progressDayMs

/// Monday 2023-09-04T00:00:00Z — the same week-aligned anchor
/// `GymRepositoryProgressTests` uses.
private let progressMonday: Int64 = 1_693_785_600_000
private let progressClockNow: Int64 = progressMonday + 4 * progressWeekMs + 3 * progressDayMs

private func makeProgressFixture() throws -> GymRepository {
    let clock = FixedClock(progressClockNow)
    let database = try AppDatabase.inMemory()
    return GymRepository(dbWriter: database, clock: clock)
}

private func seedExercises(_ repository: GymRepository) throws {
    try repository.upsert(
        Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
    try repository.upsert(
        Exercise(id: "e2", name: "Barbell row", muscleGroup: .back, equipment: .barbell))
    try repository.upsert(
        Exercise(id: "e3", name: "Plank", muscleGroup: .core, equipment: .bodyweight))
}

/// Logs one completed set of `exerciseId` in its own session.
private func logSet(
    _ repository: GymRepository,
    session: String,
    exerciseId: String,
    startedAt: Int64,
    weightKg: Double,
    reps: Int,
    completed: Bool = true
) throws {
    try repository.upsert(WorkoutSession(id: session, startedAt: startedAt))
    try repository.upsert(
        WorkoutSet(
            id: "\(session)-set",
            sessionId: session,
            exerciseId: exerciseId,
            position: 0,
            weightKg: weightKg,
            reps: reps,
            completed: completed))
}

/// Three bench-press sessions — 60 × 8, 62.5 × 8, 65 × 8, one per week — plus
/// one lighter barbell-row session. Weekly volume: 480, 500, 520 = 1500.
private func seedThreeSessions(_ repository: GymRepository) throws {
    try seedExercises(repository)
    try logSet(
        repository, session: "s1", exerciseId: "e1",
        startedAt: progressMonday + progressDayMs, weightKg: 60, reps: 8)
    try logSet(
        repository, session: "s2", exerciseId: "e1",
        startedAt: progressMonday + progressWeekMs + progressDayMs, weightKg: 62.5, reps: 8)
    try logSet(
        repository, session: "s3", exerciseId: "e1",
        startedAt: progressMonday + 2 * progressWeekMs + progressDayMs, weightKg: 65, reps: 8)
    try logSet(
        repository, session: "s4", exerciseId: "e2",
        startedAt: progressMonday + 2 * progressWeekMs + 2 * progressDayMs, weightKg: 100, reps: 1)
}

@MainActor
struct ProgressTabViewModelTests {

    // MARK: - Empty

    @Test func withoutACompletedSetTheWholeTabIsEmpty() throws {
        let repository = try makeProgressFixture()
        try seedExercises(repository)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        #expect(model.state == .empty)
        #expect(model.topExercises.isEmpty)
        #expect(model.selected == nil)
        #expect(model.points.isEmpty)
        #expect(model.weeklyVolume.isEmpty)
        #expect(model.best == nil)
    }

    @Test func aPlannedButUnfinishedSetDoesNotCountAsProgress() throws {
        let repository = try makeProgressFixture()
        try seedExercises(repository)
        try logSet(
            repository, session: "s1", exerciseId: "e1",
            startedAt: progressMonday + progressDayMs, weightKg: 60, reps: 8, completed: false)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        #expect(model.state == .empty)
    }

    // MARK: - Not enough data

    @Test func oneSessionIsNotEnoughToDrawATrend() throws {
        let repository = try makeProgressFixture()
        try seedExercises(repository)
        try logSet(
            repository, session: "s1", exerciseId: "e1",
            startedAt: progressMonday + progressDayMs, weightKg: 60, reps: 8)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        #expect(model.state == .notEnoughData)
        #expect(model.points.count == 1)
        let selected = try #require(model.selected)
        #expect(selected.id == "e1")
    }

    // MARK: - Ready

    @Test func threeSessionsFillTheChart() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        #expect(model.state == .ready)
        let selected = try #require(model.selected)
        #expect(selected.id == "e1")
        #expect(model.exerciseName == "Bench press")
        #expect(model.accentGroup == "chest")

        #expect(model.points.count == 3)
        #expect(model.points[0].weightKg == 60)
        #expect(model.points[1].weightKg == 62.5)
        #expect(model.points[2].weightKg == 65)
        // The point is keyed on its session, not on its timestamp.
        #expect(model.points[0].id == "s1")
        #expect(model.points[2].id == "s3")
    }

    @Test func weeklyVolumeFollowsTheSelectedExercise() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        // Twelve buckets always: the running week and the eleven before it.
        // The anchor sits seven weeks back in that window.
        #expect(model.weeklyVolume.count == 12)
        #expect(model.weeklyVolume[7].volumeKg == 480)
        #expect(model.weeklyVolume[8].volumeKg == 500)
        #expect(model.weeklyVolume[9].volumeKg == 520)
        #expect(model.weeklyVolume[0].volumeKg == 0)
        #expect(model.weeklyVolume[11].volumeKg == 0)

        let expected = "12 weeks, \(Double(1_500).formatted()) kg in total"
        #expect(model.volumeAccessibilityValue == expected)
    }

    /// A layoff has to draw as empty bars. Two weeks of training with a gap
    /// between them would otherwise collapse into two neighbours and read as
    /// "trained twice in a row".
    @Test func weeksWithoutTrainingAreZeroFilled() throws {
        let repository = try makeProgressFixture()
        try seedExercises(repository)
        try logSet(
            repository, session: "s1", exerciseId: "e1",
            startedAt: progressMonday + progressDayMs, weightKg: 60, reps: 8)
        try logSet(
            repository, session: "s2", exerciseId: "e1",
            startedAt: progressMonday + 2 * progressWeekMs + progressDayMs, weightKg: 65, reps: 8)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        #expect(model.weeklyVolume.count == 12)
        #expect(model.weeklyVolume[7].volumeKg == 480)
        // The week in between was never trained.
        #expect(model.weeklyVolume[8].volumeKg == 0)
        #expect(model.weeklyVolume[9].volumeKg == 520)
    }

    /// The bars end on the week the user is in, and start eleven weeks before
    /// it — always a Monday, so the leftmost bar is a whole week.
    @Test func theBarsEndOnTheCurrentWeekAndStartOnAMonday() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        let first = try #require(model.weeklyVolume.first)
        let last = try #require(model.weeklyVolume.last)
        let firstMs = Int64(first.weekStart.timeIntervalSince1970 * 1000)
        let lastMs = Int64(last.weekStart.timeIntervalSince1970 * 1000)

        #expect(lastMs == progressMonday + 4 * progressWeekMs)
        #expect(firstMs == progressMonday - 7 * progressWeekMs)
        #expect(GymRepository.weekStart(of: firstMs) == firstMs)
    }

    @Test func theBestSetTileTakesTheHeaviestSet() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        let best = try #require(model.best)
        #expect(best.valueText == "65 kg × 8")
        #expect(best.dateText.isEmpty == false)
        #expect(model.chartAccessibilityValue == "3 sessions, from 60 kg to 65 kg")
    }

    // MARK: - Chips and selection

    @Test func theChipsAreTheSixExercisesWithTheMostVolume() throws {
        let repository = try makeProgressFixture()
        // Seven exercises, descending volume: 700, 600, … 100.
        for index in 0 ..< 7 {
            let id = "x\(index)"
            try repository.upsert(
                Exercise(id: id, name: "Lift \(index)", muscleGroup: .chest, equipment: .barbell))
            try logSet(
                repository, session: "s\(index)", exerciseId: id,
                startedAt: progressMonday + progressDayMs,
                weightKg: Double(70 - index * 10), reps: 10)
        }
        let model = ProgressTabViewModel(repository: repository)

        model.reload()

        #expect(model.topExercises.count == ProgressTabViewModel.topExerciseCount)
        #expect(model.topExercises[0].id == "x0")
        #expect(model.topExercises[5].id == "x5")
        #expect(model.chipExercises.count == 6)
    }

    @Test func pickingAnotherExerciseSwitchesEverySeries() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)
        model.reload()

        let stored = try repository.exercise(id: "e2")
        let row = try #require(stored)
        model.select(row)

        #expect(model.selected?.id == "e2")
        #expect(model.accentGroup == "back")
        #expect(model.points.count == 1)
        #expect(model.state == .notEnoughData)
    }

    /// An exercise chosen in the search sheet is outside the top six by
    /// definition — it has no volume at all. It still has to appear as a chip,
    /// otherwise the screen shows a chart no chip points at.
    @Test func anExerciseChosenInTheSearchSheetJoinsTheChips() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)
        model.reload()

        let stored = try repository.exercise(id: "e3")
        let plank = try #require(stored)
        model.select(plank)

        #expect(model.selected?.id == "e3")
        #expect(model.topExercises.count == 2)
        #expect(model.chipExercises.count == 3)
        #expect(model.chipExercises[0].id == "e3")
        #expect(model.state == .notEnoughData)
        #expect(model.points.isEmpty)
    }

    /// Selection survives a reload: a new session must not throw the user back
    /// to whatever now leads the volume ranking.
    @Test func theSelectionSurvivesAReload() throws {
        let repository = try makeProgressFixture()
        try seedThreeSessions(repository)
        let model = ProgressTabViewModel(repository: repository)
        model.reload()

        let stored = try repository.exercise(id: "e2")
        let row = try #require(stored)
        model.select(row)
        model.reload()

        #expect(model.selected?.id == "e2")
    }
}
