import Foundation
import Testing

@testable import Personal

private let detailBase: Int64 = 1_700_000_000_000

private func makeDetailRepository() throws -> GymRepository {
    let clock = FixedClock(detailBase)
    let database = try AppDatabase.inMemory()
    let repository = GymRepository(dbWriter: database, clock: clock)
    try repository.upsert(
        Exercise(
            id: "e1",
            name: "Bench press",
            muscleGroup: .chest,
            equipment: .barbell,
            notes: "Elbows at 45°"))
    return repository
}

/// The upload gate reads the token store and the sync status; the client is
/// never called by any of these tests.
@MainActor
private func makeDetail(
    repository: GymRepository,
    token: String?,
    status: SyncStatus
) -> ExerciseDetailViewModel {
    ExerciseDetailViewModel(
        exerciseId: "e1",
        repository: repository,
        api: APIClient(baseURL: URL(string: "https://detail.test")!, tokenProvider: { token }),
        tokenStore: InMemoryTokenStore(token),
        syncStatus: status)
}

@MainActor
struct ExerciseDetailViewModelTests {

    // MARK: - Loading

    @Test func loadingFillsTheHeaderFromTheRow() throws {
        let repository = try makeDetailRepository()
        let model = makeDetail(repository: repository, token: "t", status: SyncStatus())

        model.load()

        #expect(model.name == "Bench press")
        #expect(model.muscleLabel == "Chest")
        #expect(model.equipmentLabel == "Barbell")
        #expect(model.muscleGroup == "chest")
        #expect(model.notes == "Elbows at 45°")
        #expect(model.isGone == false)
    }

    @Test func aMissingExerciseSendsTheScreenBack() throws {
        let repository = try makeDetailRepository()
        try repository.softDelete(.exercise, id: "e1")
        let model = makeDetail(repository: repository, token: "t", status: SyncStatus())

        model.load()

        #expect(model.isGone)
    }

    // MARK: - The upload gate

    @Test func withoutATokenTheUploadIsClosedAndSaysWhy() throws {
        let repository = try makeDetailRepository()
        let model = makeDetail(repository: repository, token: nil, status: SyncStatus())

        model.load()

        #expect(model.hasToken == false)
        #expect(model.canUploadPhoto == false)
        #expect(model.uploadHint == "Add your API token in Settings to upload a photo.")
    }

    @Test func anEmptyTokenCountsAsNoToken() throws {
        let repository = try makeDetailRepository()
        let model = makeDetail(repository: repository, token: "", status: SyncStatus())

        model.load()

        #expect(model.hasToken == false)
        #expect(model.canUploadPhoto == false)
    }

    @Test func aFailingSyncClosesTheUpload() throws {
        let repository = try makeDetailRepository()
        let status = SyncStatus()
        status.state = .error("Check your API token in Settings")
        let model = makeDetail(repository: repository, token: "t", status: status)

        model.load()

        #expect(model.hasToken)
        #expect(model.canUploadPhoto == false)
        #expect(model.uploadHint == "Sync is failing right now. Fix that first, then try again.")
    }

    @Test func aTokenAndAHealthySyncOpenTheUpload() throws {
        let repository = try makeDetailRepository()
        let model = makeDetail(repository: repository, token: "t", status: SyncStatus())

        model.load()

        #expect(model.hasToken)
        #expect(model.canUploadPhoto)
        #expect(model.uploadHint == nil)
    }

    @Test func aSyncingStateDoesNotCloseTheUpload() throws {
        let repository = try makeDetailRepository()
        let status = SyncStatus()
        status.state = .syncing
        let model = makeDetail(repository: repository, token: "t", status: status)

        model.load()

        #expect(model.canUploadPhoto)
    }

    @Test func theTokenIsCachedUntilItIsRefreshed() throws {
        let repository = try makeDetailRepository()
        let store = InMemoryTokenStore()
        let model = ExerciseDetailViewModel(
            exerciseId: "e1",
            repository: repository,
            api: APIClient(baseURL: URL(string: "https://detail.test")!, tokenProvider: { nil }),
            tokenStore: store,
            syncStatus: SyncStatus())
        model.load()
        #expect(model.hasToken == false)

        try store.setToken("pasted-in-settings")
        // Still the cached answer: the getter does not go back to the store.
        #expect(model.hasToken == false)

        model.refreshToken()
        #expect(model.hasToken)
        #expect(model.canUploadPhoto)
    }

    // MARK: - Which keys count as a photo

    @Test func onlyAnUploadedKeyCountsAsAPhoto() {
        #expect(ExerciseDetailViewModel.isCustomPhoto(nil) == false)
        #expect(ExerciseDetailViewModel.isCustomPhoto("") == false)
        #expect(ExerciseDetailViewModel.isCustomPhoto("builtin/bench-press") == false)
        #expect(ExerciseDetailViewModel.isCustomPhoto("exercises/2026/a.jpg"))
    }

    @Test func aPhotoKeyOnTheRowShowsTheRemoveAction() throws {
        let repository = try makeDetailRepository()
        try repository.setImageKey(exerciseId: "e1", key: "exercises/2026/a.jpg")
        let model = makeDetail(repository: repository, token: "t", status: SyncStatus())

        model.load()

        #expect(model.hasPhoto)
    }

    @Test func removingThePhotoClearsTheKey() throws {
        let repository = try makeDetailRepository()
        try repository.setImageKey(exerciseId: "e1", key: "exercises/2026/a.jpg")
        let model = makeDetail(repository: repository, token: "t", status: SyncStatus())
        model.load()

        model.removePhoto()

        #expect(model.hasPhoto == false)
        let stored = try repository.exercise(id: "e1")
        #expect(stored?.imageKey == nil)
    }
}
