import Foundation
import Testing

@testable import Personal

/// The pure parts of the design layer: the symbol table, the formatters and
/// the image cache's naming. The views themselves are checked by their
/// `#Preview`s, not by unit tests.
struct ComponentsTests {

    // MARK: - Built-in art

    @Test func symbolIsNeverEmptyForAnyEquipment() {
        for equipment in Equipment.allCases {
            let name = BuiltinArt.symbol(for: "unknown-slug", equipment: equipment)
            #expect(name.isEmpty == false)
        }
    }

    @Test func cardioGetsTheRunningFigure() {
        let name = BuiltinArt.symbol(for: "unknown-slug", equipment: .machine, muscleGroup: .cardio)
        #expect(name == "figure.run")
    }

    @Test func equipmentPicksTheSymbolWhenTheSlugIsUnknown() {
        #expect(BuiltinArt.symbol(for: "x", equipment: .barbell) == "dumbbell")
        #expect(BuiltinArt.symbol(for: "x", equipment: .cable) == "cable.connector.horizontal")
        #expect(BuiltinArt.symbol(for: "x", equipment: .bodyweight) == "figure.core.training")
    }

    @Test func machineGetsTheStrengthFigure() {
        let name = BuiltinArt.symbol(for: "x", equipment: .machine)
        #expect(name == "figure.strengthtraining.traditional")
    }

    @Test func anUnknownExerciseStillGetsASymbol() {
        let name = BuiltinArt.symbol(for: "something-new")
        #expect(name == "dumbbell")
    }

    @Test func namedSlugsWinOverTheEquipmentTable() {
        let name = BuiltinArt.symbol(for: "treadmill", equipment: .machine, muscleGroup: .cardio)
        #expect(name == "figure.run.treadmill")
    }

    @Test func slugIsReadFromABuiltinKey() {
        #expect(BuiltinArt.slug(fromImageKey: "builtin/push-up") == "push-up")
    }

    @Test func slugIsEmptyForAPhotoKey() {
        #expect(BuiltinArt.slug(fromImageKey: "exercises/2026/a.jpg") == "")
    }

    // MARK: - Dates

    @Test func elapsedPadsEveryField() {
        #expect(DateFormat.elapsed(3730) == "01:02:10")
    }

    @Test func elapsedStartsAtZero() {
        #expect(DateFormat.elapsed(0) == "00:00:00")
    }

    @Test func elapsedClampsNegativeSeconds() {
        #expect(DateFormat.elapsed(-5) == "00:00:00")
    }

    @Test func elapsedCountsPastADay() {
        #expect(DateFormat.elapsed(90000) == "25:00:00")
    }

    @Test func todayIsNamedNotDated() {
        let today = Self.milliseconds(Date.now)
        #expect(DateFormat.dayHeader(today).primary == "Today")
    }

    @Test func tomorrowIsNamedNotDated() {
        let tomorrow = Self.day(after: 1)
        #expect(DateFormat.dayHeader(tomorrow).primary == "Tomorrow")
    }

    @Test func yesterdayIsNamedNotDated() {
        let yesterday = Self.day(after: -1)
        #expect(DateFormat.dayHeader(yesterday).primary == "Yesterday")
    }

    // MARK: - Toasts

    @Test func toastsCarryTheirKind() {
        let toast = ToastItem.error("No connection")
        #expect(toast.kind == ToastItem.Kind.error)
    }

    @Test func twoToastsWithTheSameTextAreDifferentItems() {
        let first = ToastItem.success("Session saved")
        let second = ToastItem.success("Session saved")
        #expect(first != second)
    }

    // MARK: - Image cache

    @Test func cacheFileNameIsTheHexSha256OfTheKey() {
        let name = ImageStore.cacheFileName(for: "exercises/abc123")
        #expect(name == "09a1826235713f675583de02d4c6e539a3dc6e1e2bb2d6e160ee2f2709c1c783")
    }

    @Test func cacheFileNameIsStable() {
        let first = ImageStore.cacheFileName(for: "exercises/one.jpg")
        let second = ImageStore.cacheFileName(for: "exercises/one.jpg")
        #expect(first == second)
    }

    @Test func differentKeysGetDifferentFiles() {
        let first = ImageStore.cacheFileName(for: "exercises/one.jpg")
        let second = ImageStore.cacheFileName(for: "exercises/two.jpg")
        #expect(first != second)
    }

    @Test func cacheFileNamesHaveNoSlashes() {
        let name = ImageStore.cacheFileName(for: "exercises/2026/09/photo.jpg")
        #expect(name.contains("/") == false)
    }

    @Test func noKeyMeansNoData() async {
        let store = ImageStore(api: Self.offlineClient(), cacheDirectory: Self.temporaryDirectory())
        let data = await store.imageData(for: nil)
        #expect(data == nil)
    }

    @Test func builtinKeysAreLeftToTheAssetCatalog() async {
        let store = ImageStore(api: Self.offlineClient(), cacheDirectory: Self.temporaryDirectory())
        let data = await store.imageData(for: "builtin/push-up")
        #expect(data == nil)
    }

    @Test func aCachedFileIsReadBackWithoutTheNetwork() async throws {
        let directory = Self.temporaryDirectory()
        let store = ImageStore(api: Self.offlineClient(), cacheDirectory: directory)
        let key = "exercises/cached.jpg"
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: ImageStore.cacheFileName(for: key))
        try bytes.write(to: file)

        let data = await store.imageData(for: key)
        #expect(data == bytes)
    }

    // MARK: - Helpers

    /// A client pointed at a host that does not resolve: any test that reaches
    /// the network fails fast instead of hanging or, worse, passing.
    private static func offlineClient() -> APIClient {
        APIClient(
            baseURL: URL(string: "https://offline.invalid")!,
            tokenProvider: { nil })
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Calendar arithmetic, not 86_400_000 ms: a day is not always 24 hours.
    private static func day(after days: Int) -> Int64 {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date.now) ?? Date.now
        return milliseconds(date)
    }

    private static func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "image-store-tests")
            .appending(path: UUID().uuidString)
    }
}
