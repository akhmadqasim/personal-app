import Foundation
import Testing

@testable import Personal

private let catalogBase: Int64 = 1_700_000_000_000

private func makeCatalogFixture() throws -> GymRepository {
    let clock = FixedClock(catalogBase)
    let database = try AppDatabase.inMemory()
    let repository = GymRepository(dbWriter: database, clock: clock)
    try repository.upsert(
        Exercise(id: "e1", name: "Bench press", muscleGroup: .chest, equipment: .barbell))
    try repository.upsert(
        Exercise(
            id: "e2", name: "Incline bench press", muscleGroup: .chest, equipment: .dumbbell))
    try repository.upsert(
        Exercise(id: "e3", name: "Lat pulldown", muscleGroup: .back, equipment: .cable))
    try repository.upsert(
        Exercise(id: "e4", name: "Back squat", muscleGroup: .quads, equipment: .barbell))
    return repository
}

@MainActor
struct ExerciseListViewModelTests {

    @Test func theCatalogListsEverythingByName() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.reload()

        #expect(model.rows.count == 4)
        #expect(model.rows[0].name == "Back squat")
        #expect(model.rows[1].name == "Bench press")
    }

    @Test func theRowMetaNamesEquipmentThenMuscleGroup() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.reload()

        let bench = try #require(model.rows.first(where: { $0.id == "e1" }))
        #expect(bench.meta == "Barbell · Chest")
        #expect(bench.muscleGroup == "chest")
    }

    @Test func aChipNarrowsTheListToOneMuscleGroup() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.select(.chest)

        #expect(model.rows.count == 2)
        #expect(model.rows[0].name == "Bench press")
        #expect(model.rows[1].name == "Incline bench press")
    }

    @Test func theAllChipClearsTheFilter() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)
        model.select(.chest)

        model.select(nil)

        #expect(model.rows.count == 4)
    }

    @Test func theSearchMatchesAnywhereInTheName() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.search = "press"
        model.reload()

        #expect(model.rows.count == 2)
        #expect(model.rows[0].name == "Bench press")
        #expect(model.rows[1].name == "Incline bench press")
    }

    @Test func theChipAndTheSearchNarrowTogether() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.muscleGroup = .chest
        model.search = "incline"
        model.reload()

        #expect(model.rows.count == 1)
        #expect(model.rows[0].name == "Incline bench press")
    }

    @Test func aSearchThatMatchesNothingEmptiesTheList() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.search = "deadlift"
        model.reload()

        #expect(model.rows.isEmpty)
    }

    @Test func theQueryKeyChangesWithBothFilters() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        let empty = model.queryKey
        model.muscleGroup = .back
        let grouped = model.queryKey
        model.search = "lat"
        let searched = model.queryKey

        #expect(empty == "|")
        #expect(grouped == "back|")
        #expect(searched == "back|lat")
    }

    // MARK: - Empty states

    @Test func aCatalogThatNeverSyncedAsksForASync() throws {
        let database = try AppDatabase.inMemory()
        let repository = GymRepository(dbWriter: database, clock: FixedClock(catalogBase))
        let model = ExerciseListViewModel(repository: repository)

        model.reload()

        #expect(model.rows.isEmpty)
        #expect(model.emptyState == ExerciseListEmptyState.needsSync)
    }

    @Test func aSearchThatMatchesNothingIsNotAMissingCatalog() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.search = "deadlift"
        model.reload()

        #expect(model.emptyState == ExerciseListEmptyState.noMatches)
    }

    @Test func aChipThatMatchesNothingIsNotAMissingCatalogEither() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.select(.calves)

        #expect(model.rows.isEmpty)
        #expect(model.emptyState == ExerciseListEmptyState.noMatches)
    }

    @Test func aCatalogWithRowsHasNoEmptyState() throws {
        let repository = try makeCatalogFixture()
        let model = ExerciseListViewModel(repository: repository)

        model.reload()

        #expect(model.emptyState == nil)
    }

    // MARK: - The editor behind the "+"

    @Test func theEditorWritesANewExerciseAndTheListPicksItUp() throws {
        let repository = try makeCatalogFixture()
        let editor = ExerciseEditorViewModel(repository: repository)
        editor.name = "  Romanian deadlift  "
        editor.muscleGroup = .hamstrings
        editor.equipment = .barbell
        editor.notes = "  Hinge, soft knees  "

        let savedId = editor.save()

        let exerciseId = try #require(savedId)
        let fetched = try repository.exercise(id: exerciseId)
        let stored = try #require(fetched)
        #expect(stored.name == "Romanian deadlift")
        #expect(stored.muscleGroup == .hamstrings)
        #expect(stored.notes == "Hinge, soft knees")

        let model = ExerciseListViewModel(repository: repository)
        model.reload()
        #expect(model.rows.count == 5)
    }

    @Test func editingABuiltInRowKeepsItsIdAndItsPhoto() throws {
        let repository = try makeCatalogFixture()
        try repository.setImageKey(exerciseId: "e1", key: "exercises/2026/photo.jpg")
        let editor = ExerciseEditorViewModel(exerciseId: "e1", repository: repository)
        editor.load()
        #expect(editor.name == "Bench press")

        editor.name = "Barbell bench press"
        let savedId = editor.save()

        #expect(savedId == "e1")
        let fetched = try repository.exercise(id: "e1")
        let stored = try #require(fetched)
        #expect(stored.name == "Barbell bench press")
        #expect(stored.imageKey == "exercises/2026/photo.jpg")
    }

    @Test func aBlankNameCannotBeSaved() throws {
        let repository = try makeCatalogFixture()
        let editor = ExerciseEditorViewModel(repository: repository)
        editor.name = "   "

        #expect(editor.canSave == false)
        #expect(editor.save() == nil)
    }
}
