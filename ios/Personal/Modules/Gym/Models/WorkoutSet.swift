import Foundation
import GRDB

/// One set inside a session. `position` orders every set of the session, so
/// sets of the same exercise sit next to each other in the order they were
/// planned.
nonisolated struct WorkoutSet: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "workout_set"
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    var id: String
    var updatedAt: Int64 = 0
    var deletedAt: Int64?
    var seq: Int64?
    var dirty: Bool = false

    var sessionId: String
    var exerciseId: String
    /// Zero-based rank inside the session.
    var position: Int
    var weightKg: Double
    var reps: Int
    /// Rate of perceived exertion, 1...10; optional.
    var rpe: Double?
    /// Stored as 0/1. Only completed sets feed "last time" and Progress.
    var completed: Bool = false
}
