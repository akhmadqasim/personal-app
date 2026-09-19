import Foundation
import GRDB

/// One trip to the gym. `finishedAt` is `nil` while the session is in
/// progress; `programDayId` is `nil` for a free session.
nonisolated struct WorkoutSession: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "workout_session"
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    var id: String
    var updatedAt: Int64 = 0
    var deletedAt: Int64?
    var seq: Int64?
    var dirty: Bool = false

    /// Milliseconds since the epoch; also the sort key of the history list.
    var startedAt: Int64
    var finishedAt: Int64?
    var programDayId: String?
    var notes: String?

    /// `true` once the user tapped Finish.
    var isFinished: Bool { finishedAt != nil }
}
