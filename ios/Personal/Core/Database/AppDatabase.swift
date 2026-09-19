import Foundation
import GRDB

/// Factory for the app's SQLite connections.
///
/// Both entry points run `Migrations.migrator`, so every connection handed out
/// here is already at the latest schema version. Foreign keys are enforced
/// (spec §4); `DatabasePool` puts the file in WAL mode by itself, which is why
/// no journal-mode pragma is set here.
nonisolated enum AppDatabase {

    /// The on-disk location used by the app: `Application Support/personal.sqlite`.
    static func defaultURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        return directory.appendingPathComponent("personal.sqlite")
    }

    /// Opens — creating it when missing — the database file at `url`.
    static func open(at url: URL) throws -> DatabasePool {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
        try Migrations.migrator.migrate(pool)
        return pool
    }

    /// An empty, migrated, in-memory database. Used by tests and previews: it
    /// leaves nothing behind on the file system.
    static func inMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: makeConfiguration())
        try Migrations.migrator.migrate(queue)
        return queue
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        // Default in GRDB 7, set explicitly because the schema relies on it.
        configuration.foreignKeysEnabled = true
        return configuration
    }
}
