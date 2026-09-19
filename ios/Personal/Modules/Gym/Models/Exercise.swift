import Foundation
import GRDB

/// One movement in the catalog: built-ins pulled from the server and the
/// user's own additions, which are indistinguishable once synced.
///
/// Like every synced record it is `nonisolated` — the app defaults to
/// `@MainActor` isolation, while GRDB decodes and encodes records on its own
/// database queues.
nonisolated struct Exercise: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "exercise"
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    /// UUID string; generated locally for user-created rows.
    var id: String
    /// Milliseconds since the epoch, set on every write by `GymRepository`.
    var updatedAt: Int64 = 0
    /// Non-nil once soft-deleted. Reads filter these rows out.
    var deletedAt: Int64?
    /// Server-assigned ordering cursor; `nil` until the row has been pushed.
    var seq: Int64?
    /// `true` while the row holds local changes the server has not acked.
    var dirty: Bool = false

    var name: String
    var muscleGroup: MuscleGroup
    var equipment: Equipment
    /// Key of the user's photo in the image store; `nil` uses the built-in art.
    var imageKey: String?
    var notes: String?
}
