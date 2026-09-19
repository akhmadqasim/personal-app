import Foundation
import GRDB
import Observation

/// Shared dependency container for the app: database, repository, API client,
/// sync engine + scheduler + status, and the image store.
///
/// It is injected from the root (`.environment(_:)`) so screens never reach
/// for a global, and every member is a `let`: the graph is built once at
/// launch and never swapped. `@Observable` is there for the injection, not for
/// change tracking — the observable state lives in ``SyncStatus`` and in the
/// view models.
///
/// `@MainActor` by the module's default isolation
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`); the services it holds declare their own
/// `nonisolated` / `actor` boundaries, so the work itself never runs here.
@Observable
final class AppEnvironment {

    /// The one connection the whole app shares: the repository reads and
    /// writes through it, the sync engine replicates through it, and
    /// `ValueObservation` watches it.
    let dbWriter: any DatabaseWriter
    let repository: GymRepository
    let api: APIClient
    let syncEngine: SyncEngine
    let syncStatus: SyncStatus
    let syncScheduler: SyncScheduler
    let imageStore: ImageStore
    /// Behind a protocol so Settings can be tested without the real keychain.
    let tokenStore: any TokenStore

    /// `https://api.akhmadqasim.com` (global constraints); the bearer token
    /// comes from the keychain on every request, so changing it in Settings
    /// takes effect without rebuilding anything.
    nonisolated static let baseURL = URL(string: "https://api.akhmadqasim.com")!

    init(dbWriter: any DatabaseWriter, tokenStore: any TokenStore = KeychainTokenStore()) {
        let clock = SystemClock()
        // Captured as a local: the closure is `@Sendable` and must not reach
        // for `self`, which is not built yet.
        let store = tokenStore
        let api = APIClient(baseURL: Self.baseURL, tokenProvider: { store.token() })
        let engine = SyncEngine(db: dbWriter, api: api, clock: clock)
        let status = SyncStatus()

        self.dbWriter = dbWriter
        self.repository = GymRepository(dbWriter: dbWriter, clock: clock)
        self.api = api
        self.syncEngine = engine
        self.syncStatus = status
        self.syncScheduler = SyncScheduler(engine: engine, status: status)
        self.imageStore = ImageStore(api: api)
        self.tokenStore = tokenStore
    }

    /// The environment the app runs on: a `DatabasePool` at
    /// `Application Support/personal.sqlite`.
    ///
    /// A database that cannot be opened is fatal on purpose. This is a
    /// personal app with one user: there is no degraded mode worth shipping —
    /// every screen reads from SQLite — and a crash report naming the path
    /// beats a blank screen that silently drops workouts.
    static func live() -> AppEnvironment {
        do {
            let url = try AppDatabase.defaultURL()
            let pool = try AppDatabase.open(at: url)
            return AppEnvironment(dbWriter: pool)
        } catch {
            fatalError("Personal could not open Application Support/personal.sqlite: \(error)")
        }
    }

    /// An empty in-memory environment for `#Preview`s and tests: same
    /// migrations, nothing written to disk.
    static func preview() -> AppEnvironment {
        do {
            let database = try AppDatabase.inMemory()
            return AppEnvironment(dbWriter: database)
        } catch {
            fatalError("Personal could not open an in-memory database: \(error)")
        }
    }
}
