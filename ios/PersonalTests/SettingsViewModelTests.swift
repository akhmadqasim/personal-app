import Foundation
import Testing

@testable import Personal

/// A client pointed at a host nothing answers on; the tests that use it never
/// make a request.
@MainActor
private func makeOfflineClient() -> APIClient {
    APIClient(baseURL: URL(string: "https://settings.test")!, tokenProvider: { nil })
}

@MainActor
private func makeSettings(
    store: any TokenStore,
    api: APIClient? = nil,
    status: SyncStatus? = nil
) -> SettingsViewModel {
    SettingsViewModel(
        tokenStore: store,
        syncStatus: status ?? SyncStatus(),
        api: api ?? makeOfflineClient())
}

@MainActor
struct SettingsViewModelTests {

    // MARK: - About

    @Test func theAboutLineNamesTheVersionAndTheBuild() {
        #expect(SettingsViewModel.aboutText(version: "1.2", build: "34") == "Version 1.2 (34)")
    }

    @Test func theAboutLineFallsBackWhenTheBundleSaysNothing() {
        #expect(SettingsViewModel.aboutText(version: nil, build: nil) == "Version — (—)")
        #expect(SettingsViewModel.aboutText(version: "", build: "7") == "Version — (7)")
    }

    @Test func theInstanceAboutLineUsesTheValuesItWasGiven() {
        let model = SettingsViewModel(
            tokenStore: InMemoryTokenStore(),
            syncStatus: SyncStatus(),
            api: makeOfflineClient(),
            appVersion: "2.0",
            appBuild: "9")

        #expect(model.aboutText == "Version 2.0 (9)")
    }

    // MARK: - Token

    @Test func anEmptyStoreReportsNoToken() {
        let model = makeSettings(store: InMemoryTokenStore())

        model.load()

        #expect(model.hasToken == false)
    }

    @Test func savingATokenTrimsItAndClearsTheField() {
        let store = InMemoryTokenStore()
        let model = makeSettings(store: store)
        model.load()

        model.tokenText = "  secret-token  "
        model.saveToken()

        #expect(store.token() == "secret-token")
        #expect(model.tokenText.isEmpty)
        #expect(model.hasToken)
        #expect(model.toast?.kind == .success)
    }

    @Test func aBlankTokenIsRefused() {
        let store = InMemoryTokenStore()
        let model = makeSettings(store: store)

        model.tokenText = "   "
        model.saveToken()

        #expect(store.token() == nil)
        #expect(model.toast?.kind == .error)
    }

    @Test func removingTheTokenEmptiesTheStore() {
        let store = InMemoryTokenStore("secret-token")
        let model = makeSettings(store: store)
        model.load()
        #expect(model.hasToken)

        model.clearToken()

        #expect(store.token() == nil)
        #expect(model.hasToken == false)
    }

    // MARK: - Sync state

    @Test func theStateLineMirrorsTheSyncStatus() {
        let status = SyncStatus()
        let model = makeSettings(store: InMemoryTokenStore(), status: status)

        #expect(model.stateText == "Idle")
        #expect(model.isSyncFailing == false)
        #expect(model.lastSyncedText == "Never")

        status.state = .syncing
        #expect(model.stateText == "Syncing…")

        status.state = .error("Check your API token in Settings")
        #expect(model.stateText == "Check your API token in Settings")
        #expect(model.isSyncFailing)
    }

    @Test func aSuccessfulRunGetsARelativeLastSyncedLine() {
        let status = SyncStatus()
        status.lastSyncedAt = Date()
        let model = makeSettings(store: InMemoryTokenStore(), status: status)

        #expect(model.lastSyncedText.isEmpty == false)
        #expect(model.lastSyncedText != "Never")
    }

    // MARK: - Export

    @Test func theExportFileNameCarriesTheDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 7
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)

        #expect(SettingsViewModel.exportFileName(for: date) == "gym-export-20260907.json")
    }

    @Test func exportingWritesTheServerPayloadToATempFile() async throws {
        let server = StubServer()
        server.enqueue(#"{"exercises":[],"programs":[]}"#)
        let api = APIClient(
            baseURL: server.baseURL,
            tokenProvider: { "secret-token" },
            session: server.makeSession())
        let model = makeSettings(store: InMemoryTokenStore("secret-token"), api: api)

        await model.export()

        let url = try #require(model.exportURL)
        #expect(url.lastPathComponent.hasPrefix("gym-export-"))
        #expect(url.pathExtension == "json")
        let written = try Data(contentsOf: url)
        #expect(written.isEmpty == false)
        #expect(model.toast?.kind == .success)

        let requests = server.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url.path() == "/api/gym/export")
        #expect(request.header("Authorization") == "Bearer secret-token")
    }

    @Test func aFailedExportShowsTheFixedSentence() async throws {
        let server = StubServer()
        server.enqueue(#"{"code":"unauthorized","message":"nope"}"#, status: 401)
        let api = APIClient(
            baseURL: server.baseURL,
            tokenProvider: { "secret-token" },
            session: server.makeSession())
        let model = makeSettings(store: InMemoryTokenStore("secret-token"), api: api)

        await model.export()

        #expect(model.exportURL == nil)
        #expect(model.toast?.kind == .error)
        #expect(model.toast?.message == ApiError.unauthorized.message)
    }
}
