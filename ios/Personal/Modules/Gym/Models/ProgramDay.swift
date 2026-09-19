import Foundation
import GRDB

/// One day of a program ("Push A"), ordered by `position` within its program.
nonisolated struct ProgramDay: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "program_day"
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase

    var id: String
    var updatedAt: Int64 = 0
    var deletedAt: Int64?
    var seq: Int64?
    var dirty: Bool = false

    var programId: String
    var name: String
    /// Zero-based rank inside the program; drives "next up" selection.
    var position: Int
}
