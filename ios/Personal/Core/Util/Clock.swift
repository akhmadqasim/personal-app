import Foundation
import Synchronization

/// Source of "now", in milliseconds since the Unix epoch — the unit every
/// `updated_at`, `started_at` and `finished_at` column stores.
///
/// It is a dependency rather than a call to `Date()` so tests can pin time and
/// assert on exact timestamps instead of sleeping.
///
/// `nowMs()` is `nonisolated` on purpose: the repository and the sync engine
/// call it from database queues, far from the main actor.
///
/// Named `AppClock`, not `Clock`, so it does not shadow `Swift.Clock` — the
/// sync scheduler debounces with `ContinuousClock`, which needs that name.
protocol AppClock: Sendable {
    /// Milliseconds since 1970-01-01T00:00:00Z.
    nonisolated func nowMs() -> Int64
}

/// The real clock.
nonisolated struct SystemClock: AppClock {
    init() {}

    func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

/// A clock the tests move by hand. Thread-safe so it can be read from a
/// database queue while the test sets it from the main actor.
nonisolated final class FixedClock: AppClock {
    private let storage: Mutex<Int64>

    init(_ milliseconds: Int64 = 0) {
        self.storage = Mutex(milliseconds)
    }

    func nowMs() -> Int64 {
        storage.withLock { $0 }
    }

    /// Jumps to an absolute instant.
    func set(_ milliseconds: Int64) {
        storage.withLock { $0 = milliseconds }
    }

    /// Moves forward (or back, with a negative value) by `milliseconds`.
    func advance(by milliseconds: Int64) {
        storage.withLock { $0 += milliseconds }
    }
}
