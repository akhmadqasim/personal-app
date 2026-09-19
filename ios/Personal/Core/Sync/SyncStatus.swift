import Foundation
import Observation

/// Where the sync engine stands right now.
///
/// Declared at file scope and `nonisolated` so an outcome can be built off the
/// main actor and compared anywhere; only the observable box around it is
/// main-actor bound.
nonisolated enum SyncState: Equatable, Sendable {
    /// Nothing to do; the last run, if any, succeeded.
    case idle
    /// A run is in flight.
    case syncing
    /// The last run failed. The text is the fixed English sentence from
    /// ``ApiError/message`` — Settings shows it as a line, screens as a toast.
    case error(String)
}

/// The observable sync state the UI reads (spec §5): one line in Settings, a
/// toast on failure.
///
/// Only ``SyncScheduler`` writes to it.
@Observable
@MainActor
final class SyncStatus {

    typealias State = SyncState

    /// Current state; starts idle, before the first run.
    var state: SyncState = .idle

    /// When the last successful run finished, or `nil` until then.
    var lastSyncedAt: Date?

    init() {}
}
