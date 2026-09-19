import Foundation
import GRDB
import os

/// What one `SyncEngine.sync()` run ended in.
nonisolated enum SyncOutcome: Equatable, Sendable {
    /// Rows written locally, rows sent, and rows the server offered that could
    /// not be written — summed over the whole run.
    case success(pulled: Int, pushed: Int, skipped: Int)
    /// The run stopped early. Nothing was applied, the cursor did not move and
    /// dirty rows stay dirty; the next trigger retries.
    case failure(ApiError)
}

/// Two-way replication against `POST /api/sync` (spec §5).
///
/// An `actor`, not a `@MainActor` type: it awaits the database and the network,
/// and the UI only ever awaits its result. Rows are handled generically as
/// `[String: JSONValue]`, so the engine knows the table names (``SyncedTable``,
/// in foreign-key order) but never a single column name.
///
/// A run is two phases. The network round trips come first and collect their
/// pages in memory; the database is written once, at the end, in a single
/// transaction. The server pages by `seq` across all tables, and an edited
/// parent is given a *new* `seq`, so a child can perfectly well arrive one page
/// before its parent — applying page by page would hit a foreign-key error,
/// roll back, and leave the cursor stuck on that page forever.
actor SyncEngine {

    /// The server's push limit (`gym-tracker.md` §5); a larger body is a 413.
    static let maxPushRows = 500
    /// A run makes at most this many round trips, so a server that keeps
    /// answering `has_more` cannot spin forever.
    static let maxIterations = 20
    /// A 409 means another sync was writing; the request is safe to repeat.
    static let conflictRetries = 3

    private let dbWriter: any DatabaseWriter
    private let api: APIClient
    private let clock: any AppClock
    private let retryDelay: Duration

    init(
        db: any DatabaseWriter,
        api: APIClient,
        clock: any AppClock = SystemClock(),
        retryDelay: Duration = .seconds(1)
    ) {
        self.dbWriter = db
        self.api = api
        self.clock = clock
        self.retryDelay = retryDelay
    }

    /// When the last successful run finished, in milliseconds, or `nil` before
    /// the first one. Settings shows it after a relaunch.
    func lastSyncedAt() async throws -> Int64? {
        try await dbWriter.read { database in
            let value = try Int64.fetchOne(
                database,
                sql: "SELECT value FROM sync_state WHERE key = 'last_synced_at'")
            guard let value, value > 0 else { return nil }
            return value
        }
    }

    /// Pushes every dirty row and pulls everything past the cursor.
    ///
    /// The network loop sends dirty rows in chunks of at most ``maxPushRows``
    /// in foreign-key order, follows the `has_more` cursor and collects the
    /// pulled pages. The single write transaction that follows applies those
    /// pages table by table in foreign-key order, clears `dirty` on the rows
    /// that did not change while they were in flight, and stores the cursor.
    func sync() async -> SyncOutcome {
        let limit = Self.maxPushRows

        var cursor: Int64
        do {
            cursor = try await dbWriter.read { database in
                try SyncSQL.sinceSeq(database)
            }
        } catch is CancellationError {
            return .failure(.network("Sync was cancelled"))
        } catch {
            return .failure(.server("Could not read the local database"))
        }

        var pulled: [String: [JSONRow]] = [:]
        var snapshot: [PushedRow] = []
        // Rows already sent, per table: the push clears no `dirty` flag until
        // the end of the run, so the next chunk has to skip past them.
        var taken: [String: Int] = [:]
        var pushedTotal = 0

        for _ in 0 ..< Self.maxIterations {
            let skip = taken
            let batch: PushBatch
            do {
                batch = try await dbWriter.read { database in
                    try SyncSQL.snapshot(database, limit: limit, skip: skip)
                }
            } catch is CancellationError {
                return .failure(.network("Sync was cancelled"))
            } catch {
                return .failure(.server("Could not read the local database"))
            }

            let response: SyncResponse
            do {
                response = try await post(SyncRequest(sinceSeq: cursor, push: batch.rows))
            } catch let error as ApiError {
                return .failure(error)
            } catch is CancellationError {
                return .failure(.network("Sync was cancelled"))
            } catch {
                return .failure(.network(error.localizedDescription))
            }

            cursor = response.seq
            pushedTotal += batch.count
            snapshot.append(contentsOf: batch.snapshot)
            // Count what the query returned, which is what the next `OFFSET`
            // has to step over — not what survived the guards below it.
            for (name, count) in batch.fetched {
                taken[name, default: 0] += count
            }
            for (name, rows) in response.pull where rows.isEmpty == false {
                pulled[name, default: []].append(contentsOf: rows)
            }

            if response.hasMore == false && pushedTotal >= batch.dirtyTotal {
                break
            }
        }

        return await apply(pulled: pulled, snapshot: snapshot, cursor: cursor, pushed: pushedTotal)
    }

    /// Writes the whole run.
    ///
    /// The first attempt is strict: deferred foreign keys, all or nothing, so a
    /// child pulled before its parent is fine as long as the parent is in the
    /// same run. When that transaction fails — a parent dropped for a missing
    /// column leaves its child dangling, say — the second attempt is lenient:
    /// immediate foreign keys and one savepoint per row, so a row that cannot
    /// be written is skipped instead of wedging every future run on the same
    /// page.
    private func apply(
        pulled: [String: [JSONRow]],
        snapshot: [PushedRow],
        cursor: Int64,
        pushed: Int
    ) async -> SyncOutcome {
        let now = clock.nowMs()
        do {
            let result = try await dbWriter.write { database in
                try SyncSQL.apply(
                    pulled: pulled,
                    snapshot: snapshot,
                    cursor: cursor,
                    now: now,
                    lenient: false,
                    in: database)
            }
            return .success(pulled: result.applied, pushed: pushed, skipped: result.skipped)
        } catch is CancellationError {
            return .failure(.network("Sync was cancelled"))
        } catch {
            SyncSQL.logger.error("Strict apply failed; retrying row by row")
        }

        do {
            let result = try await dbWriter.write { database in
                try SyncSQL.apply(
                    pulled: pulled,
                    snapshot: snapshot,
                    cursor: cursor,
                    now: now,
                    lenient: true,
                    in: database)
            }
            return .success(pulled: result.applied, pushed: pushed, skipped: result.skipped)
        } catch is CancellationError {
            return .failure(.network("Sync was cancelled"))
        } catch {
            return .failure(.server("Could not write the local database"))
        }
    }

    /// One `POST /api/sync`, retrying a 409 after ``retryDelay`` because the
    /// server rejects concurrent pushes by design.
    private func post(_ request: SyncRequest) async throws -> SyncResponse {
        var attempt = 0
        while true {
            do {
                let response: SyncResponse = try await api.postJSON("/api/sync", body: request)
                return response
            } catch let error as ApiError {
                guard error == .conflict, attempt < Self.conflictRetries else { throw error }
                attempt += 1
                // Not `try?`: a cancelled sleep must end the run, not push again.
                try await Task.sleep(for: retryDelay)
            }
        }
    }
}

/// One row the engine sent, remembered so `dirty` is only cleared when the row
/// did not change while the request was in flight (spec §5).
private nonisolated struct PushedRow: Sendable {
    var table: String
    var id: String
    var updatedAt: Int64
}

/// One chunk of the push, read in a single transaction.
private nonisolated struct PushBatch: Sendable {
    /// Rows to send, per table name.
    var rows: [String: [JSONRow]]
    /// The same rows as `(table, id, updated_at)` triples.
    var snapshot: [PushedRow]
    /// Rows the chunk query returned per table, including any the conversion
    /// then dropped. This is what the next chunk's `OFFSET` steps over.
    var fetched: [String: Int]
    /// How many rows this chunk sends.
    var count: Int
    /// How many dirty rows the database held when the chunk was read; the run
    /// keeps going until at least that many have been sent.
    var dirtyTotal: Int
}

/// What one write transaction did.
private nonisolated struct ApplyResult: Sendable {
    /// Rows written locally.
    var applied: Int
    /// Rows the server offered that could not be written: a missing `NOT NULL`
    /// column, or a per-row failure in lenient mode. A row that simply lost the
    /// last-writer-wins check is not counted — nothing went wrong there.
    var skipped: Int
}

/// What happened to one pulled row.
private nonisolated enum RowOutcome: Sendable {
    /// Written to the table.
    case written
    /// The local row was newer and dirty, so it stays.
    case keptLocal
    /// The row could not be written at all.
    case dropped
}

/// Columns of one table: what may be written, and what must be present.
private nonisolated struct TableSchema: Sendable {
    /// Every column name.
    var columns: Set<String>
    /// `NOT NULL` columns without a default — an incoming row missing one of
    /// these cannot be inserted at all.
    var required: Set<String>
}

/// The generic SQL half of the engine.
///
/// A `nonisolated` namespace: every function here runs inside a GRDB
/// transaction block, on the database queue, far from any actor.
private nonisolated enum SyncSQL {

    static let logger = Logger(subsystem: "com.akhmadqasim.personal", category: "sync")

    // MARK: - Reading

    /// The pull cursor; 0 before the first successful sync.
    static func sinceSeq(_ db: Database) throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = 'since_seq'") ?? 0
    }

    /// The next chunk of the push: dirty rows table by table in foreign-key
    /// order until the budget is spent, skipping the rows earlier chunks of
    /// this run already sent.
    ///
    /// Filling the budget in that order is what makes chunking safe — a table
    /// is exhausted before the next one is touched, so a parent row is never
    /// left for a later chunk than its children, and an unrepairable 422 on a
    /// foreign key cannot happen.
    static func snapshot(_ db: Database, limit: Int, skip: [String: Int]) throws -> PushBatch {
        var rows: [String: [JSONRow]] = [:]
        var pushed: [PushedRow] = []
        var fetchedCounts: [String: Int] = [:]
        var budget = limit

        for table in SyncedTable.allCases {
            if budget <= 0 { break }
            let name = table.rawValue
            let offset = skip[name] ?? 0
            let fetched = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM \(name)
                    WHERE dirty = 1
                    ORDER BY updated_at, id
                    LIMIT \(budget) OFFSET \(offset)
                    """)
            if fetched.isEmpty { continue }
            fetchedCounts[name] = fetched.count
            budget -= fetched.count

            var wire: [JSONRow] = []
            wire.reserveCapacity(fetched.count)
            for row in fetched {
                let json = jsonRow(from: row)
                guard let id = json["id"]?.text else { continue }
                guard let updatedAt = json["updated_at"]?.intValue else { continue }
                wire.append(json)
                pushed.append(PushedRow(table: name, id: id, updatedAt: updatedAt))
            }
            if wire.isEmpty { continue }
            rows[name] = wire
        }

        let total = try dirtyRowCount(db)
        return PushBatch(
            rows: rows,
            snapshot: pushed,
            fetched: fetchedCounts,
            count: pushed.count,
            dirtyTotal: total)
    }

    /// How many rows still carry local changes, across every synced table.
    static func dirtyRowCount(_ db: Database) throws -> Int {
        var total = 0
        for table in SyncedTable.allCases {
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(table.rawValue) WHERE dirty = 1")
            total += count ?? 0
        }
        return total
    }

    // MARK: - Writing

    /// Applies a whole run inside the caller's transaction.
    ///
    /// Strict mode (`lenient == false`) defers the foreign-key checks to the
    /// commit, so the run is all or nothing: a failure leaves the database
    /// exactly as it was, the cursor stays put and the next run asks for the
    /// same pages again. Lenient mode checks foreign keys immediately and wraps
    /// every row in a savepoint, so one impossible row costs only itself.
    static func apply(
        pulled: [String: [JSONRow]],
        snapshot: [PushedRow],
        cursor: Int64,
        now: Int64,
        lenient: Bool,
        in db: Database
    ) throws -> ApplyResult {
        if lenient == false {
            // Within this transaction a child may reference a parent that is
            // inserted a few statements later. The constraints are still
            // checked, at commit.
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
        }

        var applied = 0
        var skipped = 0
        for table in SyncedTable.allCases {
            guard let rows = pulled[table.rawValue] else { continue }
            if rows.isEmpty { continue }
            let name = table.rawValue
            let schema = try tableSchema(db, table: name)
            for row in rows {
                let outcome = try applyRow(row, table: name, schema: schema, lenient: lenient, in: db)
                switch outcome {
                case .written:
                    applied += 1
                case .dropped:
                    skipped += 1
                case .keptLocal:
                    break
                }
            }
        }

        // A row whose `updated_at` moved while the request was in flight stays
        // dirty and goes out again on the next run.
        for pushed in snapshot {
            try db.execute(
                sql: "UPDATE \(pushed.table) SET dirty = 0 WHERE id = ? AND updated_at = ?",
                arguments: [pushed.id, pushed.updatedAt])
        }

        try writeState(db, sinceSeq: cursor, now: now)
        return ApplyResult(applied: applied, skipped: skipped)
    }

    /// One pulled row, wrapped in a savepoint when the caller asked for
    /// leniency so a failure costs only this row.
    static func applyRow(
        _ row: JSONRow,
        table: String,
        schema: TableSchema,
        lenient: Bool,
        in db: Database
    ) throws -> RowOutcome {
        if lenient == false {
            return try applyPulled(row, table: table, schema: schema, in: db)
        }
        var outcome = RowOutcome.dropped
        do {
            try db.inSavepoint {
                outcome = try applyPulled(row, table: table, schema: schema, in: db)
                return .commit
            }
        } catch {
            logger.error("Skipped an incoming \(table, privacy: .public) row the database refused")
            return .dropped
        }
        return outcome
    }

    /// Last-writer-wins for one pulled row: a dirty local row that is newer
    /// wins, everything else is overwritten with `dirty = 0`.
    ///
    /// `INSERT OR REPLACE` deletes the old row before inserting the new one,
    /// which is safe here: SQLite checks foreign keys at the end of the
    /// statement — and, with `defer_foreign_keys`, of the transaction — by
    /// which time the same id is back in the table, so children of a replaced
    /// parent survive.
    static func applyPulled(
        _ row: JSONRow,
        table: String,
        schema: TableSchema,
        in db: Database
    ) throws -> RowOutcome {
        guard let id = row["id"]?.text else { return .dropped }
        guard let incomingUpdatedAt = row["updated_at"]?.intValue else { return .dropped }

        // A row missing a `NOT NULL` column cannot be inserted at all. Dropping
        // that one row is recoverable: the server sends it again after the next
        // edit.
        for column in schema.required {
            let value = row[column]
            if value == nil || value == JSONValue.null {
                logger.error(
                    "Skipped an incoming \(table, privacy: .public) row missing \(column, privacy: .public)")
                return .dropped
            }
        }

        let local = try Row.fetchOne(
            db,
            sql: "SELECT updated_at, dirty FROM \(table) WHERE id = ?",
            arguments: [id])
        if let local {
            let localUpdatedAt: Int64 = local["updated_at"]
            let localDirty: Int64 = local["dirty"]
            if localDirty == 1 && localUpdatedAt > incomingUpdatedAt { return .keptLocal }
        }

        // Unknown columns are dropped rather than failing the whole batch: the
        // server may run one migration ahead of this build.
        let names = row.keys.filter { schema.columns.contains($0) && $0 != "dirty" }.sorted()
        if names.isEmpty { return .dropped }
        let columnList = names.joined(separator: ", ")
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let values = names.map { databaseValue(from: row[$0] ?? .null) }

        try db.execute(
            sql: "INSERT OR REPLACE INTO \(table) (\(columnList), dirty) VALUES (\(placeholders), 0)",
            arguments: StatementArguments(values))
        return .written
    }

    /// Stores the pull cursor and the time of this run.
    static func writeState(_ db: Database, sinceSeq: Int64, now: Int64) throws {
        try db.execute(
            sql: """
                INSERT INTO sync_state (key, value) VALUES ('since_seq', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
            arguments: [sinceSeq])
        try db.execute(
            sql: """
                INSERT INTO sync_state (key, value) VALUES ('last_synced_at', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
            arguments: [now])
    }

    // MARK: - Row conversion

    /// The columns of `table`, and which of them an incoming row must carry.
    static func tableSchema(_ db: Database, table: String) throws -> TableSchema {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        var columns: Set<String> = []
        var required: Set<String> = []
        for row in rows {
            let name: String = row["name"]
            columns.insert(name)
            let notNull: Int64 = row["notnull"]
            let defaultValue: String? = row["dflt_value"]
            if notNull == 1 && defaultValue == nil {
                required.insert(name)
            }
        }
        return TableSchema(columns: columns, required: required)
    }

    /// A fetched row as a wire row.
    ///
    /// `dirty` is local-only and `seq` belongs to the server, which assigns a
    /// fresh one to every row it accepts — sending either back would be noise.
    static func jsonRow(from row: Row) -> JSONRow {
        var result: JSONRow = [:]
        for columnName in row.columnNames {
            if columnName == "dirty" { continue }
            if columnName == "seq" { continue }
            let value: DatabaseValue = row[columnName]
            result[columnName] = jsonValue(from: value)
        }
        return result
    }

    /// SQLite storage class → wire value.
    static func jsonValue(from value: DatabaseValue) -> JSONValue {
        switch value.storage {
        case .null:
            return .null
        case .int64(let number):
            return .int(number)
        case .double(let number):
            return .double(number)
        case .string(let text):
            return .string(text)
        case .blob:
            // No synced column stores one; dropping it beats crashing.
            return .null
        }
    }

    /// Wire value → SQLite storage class.
    static func databaseValue(from value: JSONValue) -> DatabaseValue {
        switch value {
        case .null:
            return DatabaseValue.null
        case .bool(let flag):
            return Int64(flag ? 1 : 0).databaseValue
        case .int(let number):
            return number.databaseValue
        case .double(let number):
            return number.databaseValue
        case .string(let text):
            return text.databaseValue
        }
    }
}
