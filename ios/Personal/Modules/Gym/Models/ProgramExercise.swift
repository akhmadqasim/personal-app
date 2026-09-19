import Foundation
import GRDB

/// A planned exercise inside a program day, with the targets a new session is
/// prefilled from when no completed set exists yet.
nonisolated struct ProgramExercise: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "program_exercise"
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    var id: String
    var updatedAt: Int64 = 0
    var deletedAt: Int64?
    var seq: Int64?
    var dirty: Bool = false

    var programDayId: String
    var exerciseId: String
    /// Zero-based rank inside the day.
    var position: Int
    /// How many `workout_set` rows `startSession(from:)` creates.
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double?
    var restSeconds: Int?
}
