import Foundation
import Observation

/// Drives the Settings sheet (spec §6): the API token, the sync controls, the
/// export and the About line.
///
/// The token goes through a ``TokenStore`` rather than ``Keychain`` directly,
/// so the save path can be tested without writing to the simulator's real
/// keychain — which every other test in the run shares.
@Observable
@MainActor
final class SettingsViewModel {

    /// What the user is typing into the secure field. Cleared on save: the
    /// stored token is never read back into the UI.
    var tokenText = ""
    var toast: ToastItem?

    private(set) var hasToken = false
    /// A sync or an export is in flight; the buttons are dead meanwhile.
    private(set) var isWorking = false
    /// The file `ShareLink` hands to the share sheet, once there is one.
    private(set) var exportURL: URL?

    /// Read straight by the view for the live state line.
    let syncStatus: SyncStatus

    private let tokenStore: any TokenStore
    private let scheduler: SyncScheduler?
    private let api: APIClient
    private let appVersion: String?
    private let appBuild: String?

    init(
        tokenStore: any TokenStore,
        syncStatus: SyncStatus,
        api: APIClient,
        scheduler: SyncScheduler? = nil,
        appVersion: String? = nil,
        appBuild: String? = nil
    ) {
        self.tokenStore = tokenStore
        self.syncStatus = syncStatus
        self.api = api
        self.scheduler = scheduler
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    // MARK: - About

    static func bundleVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static func bundleBuild() -> String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// "Version 1.0 (12)". An em dash stands in for a value the bundle does
    /// not carry, which happens in a test host.
    nonisolated static func aboutText(version: String?, build: String?) -> String {
        var shownVersion = "—"
        if let version, version.isEmpty == false {
            shownVersion = version
        }
        var shownBuild = "—"
        if let build, build.isEmpty == false {
            shownBuild = build
        }
        return "Version \(shownVersion) (\(shownBuild))"
    }

    /// Falls back to the running bundle when the caller did not pin a value —
    /// the defaults stay literal `nil` so the initialiser has no isolated
    /// default argument to evaluate.
    var aboutText: String {
        let version = appVersion ?? Self.bundleVersion()
        let build = appBuild ?? Self.bundleBuild()
        return Self.aboutText(version: version, build: build)
    }

    // MARK: - Sync state

    /// "Idle", "Syncing…", or the fixed sentence of the failure (spec §8).
    var stateText: String {
        switch syncStatus.state {
        case .idle: return "Idle"
        case .syncing: return "Syncing…"
        case .error(let message): return message
        }
    }

    var isSyncFailing: Bool {
        if case .error = syncStatus.state {
            return true
        }
        return false
    }

    /// "2 minutes ago", or "Never" before the first successful run.
    var lastSyncedText: String {
        guard let date = syncStatus.lastSyncedAt else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    // MARK: - Token

    func load() {
        let stored = tokenStore.token()
        if let stored, stored.isEmpty == false {
            hasToken = true
        } else {
            hasToken = false
        }
    }

    /// Saves the token and syncs at once (spec §6: changing it triggers a
    /// sync), so the user finds out on this screen whether it works.
    func saveToken() {
        let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            toast = .error("Paste a token first.")
            return
        }
        do {
            try tokenStore.setToken(trimmed)
            tokenText = ""
            load()
            scheduler?.trigger(.manual)
            toast = .success("Token saved")
        } catch {
            toast = .error("Could not save the token to the keychain.")
        }
    }

    func clearToken() {
        tokenStore.deleteToken()
        tokenText = ""
        load()
        toast = .success("Token removed")
    }

    // MARK: - Sync

    /// "Sync now": runs the engine and reports the state it ended in.
    func syncNow() async {
        await run(successMessage: "Synced")
    }

    /// "Test connection". A sync is exactly the round trip worth testing: it
    /// posts to `/api/sync` with the stored bearer token and comes back with
    /// either a cursor or an ``ApiError``.
    func testConnection() async {
        await run(successMessage: "Connection is working")
    }

    private func run(successMessage: String) async {
        guard isWorking == false else { return }
        isWorking = true
        await scheduler?.syncNow()
        isWorking = false
        if case .error(let message) = syncStatus.state {
            Haptics.error()
            toast = .error(message)
        } else {
            Haptics.success()
            toast = .success(successMessage)
        }
    }

    // MARK: - Export

    /// Downloads the export and drops it in the temporary directory, where
    /// `ShareLink` can hand the file itself — not its bytes — to the share
    /// sheet.
    func export() async {
        guard isWorking == false else { return }
        isWorking = true
        do {
            let response = try await api.getData("/api/gym/export")
            let url = FileManager.default.temporaryDirectory
                .appending(path: Self.exportFileName(for: Date()))
            try response.0.write(to: url, options: .atomic)
            exportURL = url
            isWorking = false
            toast = .success("Export ready to share")
        } catch let error as ApiError {
            isWorking = false
            toast = .error(error.message)
        } catch {
            isWorking = false
            toast = .error("Could not write the export file.")
        }
    }

    /// `gym-export-20260919.json`. Built by hand rather than with a
    /// `DateFormatter`: the name has to be the same in every locale and
    /// calendar, and `%d` on an `Int` is a trap worth avoiding.
    nonisolated static func exportFileName(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        let monthText = month < 10 ? "0\(month)" : "\(month)"
        let dayText = day < 10 ? "0\(day)" : "\(day)"
        return "gym-export-\(year)\(monthText)\(dayText).json"
    }
}
