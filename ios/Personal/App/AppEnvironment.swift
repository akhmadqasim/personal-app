import Observation

/// Shared dependency container for the app: database, API client, sync engine,
/// image store and settings once those exist. Empty for now — it is injected
/// from the start so screens never reach for a global.
///
/// `@MainActor` by default isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`); the
/// services it will hold declare their own `nonisolated` / `actor` boundaries.
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()
}
