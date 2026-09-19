import Foundation
import GRDB

/// A training plan: a named set of days the user cycles through. At most one
/// program is active at a time, and Today reads from that one.
nonisolated struct Program: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "program"
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    var id: String
    var updatedAt: Int64 = 0
    var deletedAt: Int64?
    var seq: Int64?
    var dirty: Bool = false

    var name: String
    /// Stored as `is_active` 0/1. Use `GymRepository.setActiveProgram(id:)`
    /// rather than writing it directly: it also clears the previous one.
    var isActive: Bool = false
}
