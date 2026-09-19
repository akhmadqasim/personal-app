import Foundation
import Testing

@testable import Personal

/// The same fixed anchor the other view-model suites use.
private let programsBase: Int64 = 1_700_000_000_000

private func makeProgramsFixture(
    now: Int64 = programsBase
) throws -> (GymRepository, FixedClock) {
    let clock = FixedClock(now)
    let database = try AppDatabase.inMemory()
    return (GymRepository(dbWriter: database, clock: clock), clock)
}

private func makeBenchPress() -> Exercise {
    Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell)
}

@MainActor
struct ProgramsViewModelTests {

    // MARK: - The list

    @Test func theListStartsEmpty() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)

        model.reload()

        #expect(model.programs.isEmpty)
    }

    @Test func theFirstProgramBecomesTheActiveOne() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)

        let firstId = model.createProgram(name: "  Push Pull Legs  ")

        #expect(firstId != nil)
        #expect(model.programs.count == 1)
        #expect(model.programs[0].name == "Push Pull Legs")
        #expect(model.programs[0].isActive)
    }

    @Test func aSecondProgramDoesNotStealTheActiveFlag() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)

        model.createProgram(name: "Push Pull Legs")
        model.createProgram(name: "Upper Lower")

        #expect(model.programs.count == 2)
        let active = model.programs.filter(\.isActive)
        #expect(active.count == 1)
        #expect(active[0].name == "Push Pull Legs")
    }

    @Test func aBlankNameIsRefused() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)

        let created = model.createProgram(name: "   ")

        #expect(created == nil)
        #expect(model.programs.isEmpty)
    }

    @Test func makingAProgramActiveClearsThePreviousFlag() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)
        model.createProgram(name: "Push Pull Legs")
        let secondId = model.createProgram(name: "Upper Lower")
        let second = try #require(secondId)

        model.makeActive(second)

        let active = model.programs.filter(\.isActive)
        #expect(active.count == 1)
        #expect(active[0].name == "Upper Lower")
    }

    @Test func aDeletedProgramLeavesTheList() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)
        let createdId = model.createProgram(name: "Push Pull Legs")
        let programId = try #require(createdId)

        model.delete(programId)

        #expect(model.programs.isEmpty)
        #expect(model.toast?.kind == .success)
    }

    @Test func deletingTheOnlyProgramLeavesNoActiveOne() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)
        let programId = try #require(model.createProgram(name: "Push Pull Legs"))

        model.delete(programId)

        let active = try repository.activeProgram()
        #expect(active == nil)
    }

    @Test func deletingTheActiveProgramPromotesTheMostRecentlyUpdatedOne() throws {
        let (repository, clock) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)
        // The first one created is the active one.
        let activeId = try #require(model.createProgram(name: "Push Pull Legs"))
        clock.advance(by: 1000)
        model.createProgram(name: "Upper Lower")
        clock.advance(by: 1000)
        model.createProgram(name: "Bro Split")

        model.delete(activeId)

        #expect(model.programs.count == 2)
        let active = model.programs.filter(\.isActive)
        #expect(active.count == 1)
        #expect(active[0].name == "Bro Split")
    }

    @Test func deletingAnInactiveProgramLeavesTheFlagWhereItIs() throws {
        let (repository, clock) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)
        model.createProgram(name: "Push Pull Legs")
        clock.advance(by: 1000)
        let sparedId = try #require(model.createProgram(name: "Upper Lower"))

        model.delete(sparedId)

        let active = model.programs.filter(\.isActive)
        #expect(active.count == 1)
        #expect(active[0].name == "Push Pull Legs")
    }

    @Test func aDeletionSheetIsDismissedOnceTheDeleteLands() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramsViewModel(repository: repository)
        let programId = try #require(model.createProgram(name: "Push Pull Legs"))
        model.pendingDeletion = model.programs.first

        model.delete(programId)

        #expect(model.pendingDeletion == nil)
    }

    @Test func theRowMetaCountsDaysAndPlannedExercises() throws {
        let (repository, _) = try makeProgramsFixture()
        try repository.upsert(makeBenchPress())
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let editor = DayEditorViewModel(dayId: dayId, repository: repository)
        editor.reload()
        editor.addExercise(makeBenchPress())

        let model = ProgramsViewModel(repository: repository)
        model.reload()

        #expect(model.programs.count == 1)
        #expect(model.programs[0].meta == "1 day · 1 exercise")
        #expect(model.programs[0].art != nil)
    }

    // MARK: - The repository method the detail screen needs

    @Test func theRepositoryFindsAProgramByIdAndHidesDeletedOnes() throws {
        let (repository, _) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")

        let found = try repository.program(id: program.id)
        #expect(found?.name == "Push Pull Legs")

        try repository.softDelete(.program, id: program.id)
        let gone = try repository.program(id: program.id)
        #expect(gone == nil)
    }

    // MARK: - Days

    @Test func daysAreAppendedInOrder() throws {
        let (repository, _) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")
        let model = ProgramDetailViewModel(programId: program.id, repository: repository)
        model.reload()

        model.addDay(name: "Push")
        model.addDay(name: "Pull")
        model.addDay(name: "Legs")

        #expect(model.days.count == 3)
        #expect(model.days[0].name == "Push")
        #expect(model.days[2].name == "Legs")

        let stored = try repository.days(of: program.id)
        #expect(stored[0].position == 0)
        #expect(stored[1].position == 1)
        #expect(stored[2].position == 2)
    }

    @Test func aMissingProgramSendsTheDetailScreenBack() throws {
        let (repository, _) = try makeProgramsFixture()
        let model = ProgramDetailViewModel(programId: "nope", repository: repository)

        model.reload()

        #expect(model.isGone)
    }

    @Test func reorderingDaysRenumbersPositionsAndStampsTheMovedRows() throws {
        let (repository, clock) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")
        let model = ProgramDetailViewModel(programId: program.id, repository: repository)
        model.reload()
        model.addDay(name: "Push")
        model.addDay(name: "Pull")
        model.addDay(name: "Legs")

        clock.advance(by: 1000)
        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(model.days[0].name == "Legs")
        #expect(model.days[1].name == "Push")
        #expect(model.days[2].name == "Pull")

        let stored = try repository.days(of: program.id)
        #expect(stored.count == 3)
        #expect(stored[0].name == "Legs")
        #expect(stored[0].position == 0)
        #expect(stored[1].position == 1)
        #expect(stored[2].position == 2)
        // Every row moved, so every row was restamped and left dirty.
        #expect(stored[0].updatedAt == programsBase + 1000)
        #expect(stored[0].dirty)
    }

    @Test func deletingADayHidesItButKeepsTheTombstone() throws {
        let (repository, _) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")
        let model = ProgramDetailViewModel(programId: program.id, repository: repository)
        model.reload()
        model.addDay(name: "Push")
        model.addDay(name: "Pull")

        model.delete(at: IndexSet(integer: 0))

        #expect(model.days.count == 1)
        #expect(model.days[0].name == "Pull")
        let dirty = try repository.dirtyCount(of: .programDay)
        #expect(dirty == 2)
    }

    // MARK: - The repository's reorder transaction

    @Test func updatePositionsStampsEveryRowWithTheSameInstant() throws {
        let (repository, clock) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")
        try repository.upsert(
            ProgramDay(id: "d0", programId: program.id, name: "Push", position: 0))
        try repository.upsert(
            ProgramDay(id: "d1", programId: program.id, name: "Pull", position: 1))
        clock.advance(by: 500)

        try repository.updatePositions(
            .programDay,
            positions: [(id: "d1", position: 0), (id: "d0", position: 1)])

        let stored = try repository.days(of: program.id)
        #expect(stored.count == 2)
        #expect(stored[0].id == "d1")
        #expect(stored[1].id == "d0")
        #expect(stored[0].updatedAt == programsBase + 500)
        #expect(stored[1].updatedAt == programsBase + 500)
        #expect(stored[0].dirty)
        #expect(stored[1].dirty)
    }

    @Test func updatePositionsIgnoresAnEmptyListAndDeletedRows() throws {
        let (repository, clock) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")
        try repository.upsert(
            ProgramDay(id: "d0", programId: program.id, name: "Push", position: 0))
        try repository.softDelete(.programDay, id: "d0")
        let deletedAtStamp = try repository.updatedAt(of: .programDay, id: "d0")
        clock.advance(by: 500)

        try repository.updatePositions(.programDay, positions: [])
        try repository.updatePositions(.programDay, positions: [(id: "d0", position: 3)])

        // The tombstone keeps the instant it was made; a reorder must not
        // resurrect it into a new push.
        let after = try repository.updatedAt(of: .programDay, id: "d0")
        #expect(after == deletedAtStamp)
    }

    // MARK: - The day editor

    @Test func addingAnExerciseToADayPlansThreeSetsOfTen() throws {
        let (repository, _) = try makeProgramsFixture()
        let exercise = makeBenchPress()
        try repository.upsert(exercise)
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))

        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()
        model.addExercise(exercise)

        let planned = try repository.programExercises(of: dayId)
        #expect(planned.count == 1)
        let first = try #require(planned.first)
        #expect(first.targetSets == 3)
        #expect(first.targetReps == 10)
        #expect(first.position == 0)
        #expect(first.targetWeightKg == nil)
        #expect(first.restSeconds == 90)

        #expect(model.rows.count == 1)
        #expect(model.rows[0].name == "Bench press")
        #expect(model.rows[0].detail == "3 × 10 · 90 s")
    }

    @Test func theTargetEditorClampsWhatItWrites() throws {
        let (repository, _) = try makeProgramsFixture()
        let exercise = makeBenchPress()
        try repository.upsert(exercise)
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()
        let rowId = try #require(model.addExercise(exercise))

        model.updateTargets(rowId, sets: 99, reps: 0, weightKg: -5, restSeconds: 9000)

        let planned = try repository.programExercises(of: dayId)
        let first = try #require(planned.first)
        #expect(first.targetSets == 10)
        #expect(first.targetReps == 1)
        #expect(first.targetWeightKg == 0)
        #expect(first.restSeconds == 300)
    }

    @Test func theRowDetailDropsWeightAndRestWhenThePlanHasNone() throws {
        let (repository, _) = try makeProgramsFixture()
        let exercise = makeBenchPress()
        try repository.upsert(exercise)
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()
        let rowId = try #require(model.addExercise(exercise))

        model.updateTargets(rowId, sets: 4, reps: 12, weightKg: 57.5, restSeconds: nil)

        #expect(model.rows[0].detail == "4 × 12 · 57.5 kg")
    }

    @Test func reorderingPlannedExercisesRenumbersPositions() throws {
        let (repository, _) = try makeProgramsFixture()
        let bench = makeBenchPress()
        let press = Exercise(
            id: "e2", name: "Overhead press", muscleGroup: .shoulders, equipment: .barbell)
        try repository.upsert(bench)
        try repository.upsert(press)
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()
        model.addExercise(bench)
        model.addExercise(press)

        model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        #expect(model.rows[0].name == "Overhead press")
        let planned = try repository.programExercises(of: dayId)
        #expect(planned[0].exerciseId == "e2")
        #expect(planned[0].position == 0)
        #expect(planned[1].position == 1)
    }

    @Test func removingAPlannedExerciseSoftDeletesIt() throws {
        let (repository, _) = try makeProgramsFixture()
        let exercise = makeBenchPress()
        try repository.upsert(exercise)
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()
        model.addExercise(exercise)

        model.delete(at: IndexSet(integer: 0))

        #expect(model.rows.isEmpty)
        let planned = try repository.programExercises(of: dayId)
        #expect(planned.isEmpty)
    }

    @Test func clearingTheTargetWeightWritesNil() throws {
        let (repository, _) = try makeProgramsFixture()
        let exercise = makeBenchPress()
        try repository.upsert(exercise)
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()
        let rowId = try #require(model.addExercise(exercise))
        model.updateTargets(rowId, sets: 3, reps: 10, weightKg: 60, restSeconds: 90)

        model.updateTargets(rowId, sets: 3, reps: 10, weightKg: nil, restSeconds: 90)

        let planned = try repository.programExercises(of: dayId)
        let first = try #require(planned.first)
        #expect(first.targetWeightKg == nil)
        #expect(model.rows[0].detail == "3 × 10 · 90 s")
    }

    @Test func renamingADayWritesItBack() throws {
        let (repository, _) = try makeProgramsFixture()
        let program = try repository.createProgram(name: "Push Pull Legs")
        let detail = ProgramDetailViewModel(programId: program.id, repository: repository)
        detail.reload()
        let dayId = try #require(detail.addDay(name: "Push A"))
        let model = DayEditorViewModel(dayId: dayId, repository: repository)
        model.reload()

        model.renameText = "  Push B  "
        model.commitRename()

        #expect(model.name == "Push B")
        let stored = try repository.day(id: dayId)
        #expect(stored?.name == "Push B")
    }
}
