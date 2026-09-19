import Foundation
import GRDB

/// What one `SyncEngine.sync()` run ended in.
nonisolated enum SyncOutcome: Equatable, Sendable {
    /// Rows sent and rows written locally, summed over every round trip of the
    /// run.
    case success(pushed: Int, pulled: Int)
    /// The run stopped early. Dirty rows stay dirty and the next trigger
    /// retries; the request is safe to repeat.
    case failure(ApiError)
}

/// Two-way replication against `POST /api/sync` (spec §5).
///
/// An `actor`, not a `@MainActor` type: it blocks on the database queue and on
/// the network, and the UI only ever awaits its result. Rows are handled
/// generically as `[String: JSONValue]`, so the engine knows the table names
/// (``SyncedTable``, in foreign-key order) but never a single column name.
actor SyncEngine {

    /// The server's push limit (`gym-tracker.md` §5); a larger body is a 413.
    static let maxPushRows = 500
    /// A run makes at most this many round trips, so a server that keeps
    /// answering `has_more` cannot spin forever.
    static let maxIterations = 20
    /// A 409 means another sync was writing; the request is safe to repeat.
    static let conflictRetries = 3

    private let db: any DatabaseWriter
    private let api: APIClient
    private let clock: any AppClock

    init(db: any DatabaseWriter, api: APIClient, clock: any AppClock = SystemClock()) {
        self.db = db
        self.api = api
        self.clock = clock
    }

    /// Pushes every dirty row and pulls everything past the cursor.
    ///
    /// One iteration is: snapshot the dirty rows (foreign-key order, at most
    /// ``maxPushRows`` in total) → `POST /api/sync` → in one write transaction
    /// apply the pull with last-writer-wins, clear `dirty` on pushed rows that
    /// did not change meanwhile, and store the new cursor. It loops while the
    /// server reports `has_more` or dirty rows are left.
    func sync() async -> SyncOutcome {
        var pushedTotal = 0
        var pulledTotal = 0

        // Read out of the type before the database closures, so they capture
        // plain local values and nothing else.
        let limit = Self.maxPushRows

        for _ in 0 ..< Self.maxIterations {
            let batch: PushBatch
            do {
                batch = try db.read { database in
                    try SyncSQL.snapshot(database, limit: limit)
                }
            } catch {
                return .failure(.server("Could not read the local database"))
            }

            let response: SyncResponse
            do {
                response = try await post(SyncRequest(sinceSeq: batch.sinceSeq, push: batch.rows))
            } catch let error as ApiError {
                return .failure(error)
            } catch {
                return .failure(.network(error.localizedDescription))
            }

            let now = clock.nowMs()
            let snapshot = batch.snapshot
            let pulled: Int
            do {
                pulled = try db.write { database in
                    try SyncSQL.apply(response, snapshot: snapshot, now: now, in: database)
                }
            } catch {
                return .failure(.server("Could not write the local database"))
            }

            pushedTotal += batch.count
            pulledTotal += pulled

            let remaining = (try? db.read { database in
                try SyncSQL.dirtyRowCount(database)
            }) ?? 0
            if response.hasMore == false && remaining == 0 {
                break
            }
        }

        return .success(pushed: pushedTotal, pulled: pulledTotal)
    }

    /// One `POST /api/sync`, retrying a 409 after a second because the server
    /// rejects concurrent pushes by design.
    private func post(_ request: SyncRequest) async throws -> SyncResponse {
        var attempt = 0
        while true {
            do {
                let response: SyncResponse = try await api.postJSON("/api/sync", body: request)
                return response
            } catch let error as ApiError {
                guard error == .conflict, attempt < Self.conflictRetries else { throw error }
                attempt += 1
                try? await Task.sleep(for: .seconds(1))
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

/// Everything one request needs, read in a single transaction.
private nonisolated struct PushBatch: Sendable {
    var sinceSeq: Int64
    var rows: [String: [JSONRow]]
    var snapshot: [PushedRow]
    var count: Int
}

/// The generic SQL half of the engine.
///
/// A `nonisolated` namespace: every function here runs inside a GRDB
/// transaction block, on the database queue, far from any actor.
private nonisolated enum SyncSQL {

    // MARK: - Reading

    /// The pull cursor; 0 before the first successful sync.
    static func sinceSeq(_ db: Database) throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = 'since_seq'") ?? 0
    }

    /// The next push: dirty rows table by table in foreign-key order until the
    /// budget is spent.
    ///
    /// Filling the budget in that order is what makes chunking safe — a table
    /// is exhausted before the next one is touched, so a parent row is never
    /// left for a later chunk than its children, and an unrepairable 422 on a
    /// foreign key cannot happen.
    static func snapshot(_ db: Database, limit: Int) throws -> PushBatch {
        var rows: [String: [JSONRow]] = [:]
        var pushed: [PushedRow] = []
        var budget = limit

        for table in SyncedTable.allCases {
            if budget <= 0 { break }
            let name = table.rawValue
            let fetched = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM \(name)
                    WHERE dirty = 1
                    ORDER BY updated_at, id
                    LIMIT \(budget)
                    """)
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
            budget -= wire.count
        }

        let cursor = try sinceSeq(db)
        return PushBatch(sinceSeq: cursor, rows: rows, snapshot: pushed, count: pushed.count)
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

    /// Applies one response inside the caller's transaction and returns how
    /// many rows were written.
    static func apply(
        _ response: SyncResponse,
        snapshot: [PushedRow],
        now: Int64,
        in db: Database
    ) throws -> Int {
        var applied = 0
        // Foreign-key order again: a child row pulled in the same response as
        // its parent must not reach the table first.
        for table in SyncedTable.allCases {
            guard let rows = response.pull[table.rawValue] else { continue }
            if rows.isEmpty { continue }
            let columns = try tableColumns(db, table: table.rawValue)
            for row in rows {
                let written = try applyPulled(row, table: table.rawValue, columns: columns, in: db)
                if written { applied += 1 }
            }
        }

        // A row whose `updated_at` moved while the request was in flight stays
        // dirty and goes out again on the next iteration.
        for pushed in snapshot {
            try db.execute(
                sql: "UPDATE \(pushed.table) SET dirty = 0 WHERE id = ? AND updated_at = ?",
                arguments: [pushed.id, pushed.updatedAt])
        }

        try writeState(db, sinceSeq: response.seq, now: now)
        return applied
    }

    /// Last-writer-wins for one pulled row: a dirty local row that is newer
    /// wins, everything else is overwritten with `dirty = 0`.
    ///
    /// `INSERT OR REPLACE` deletes the old row before inserting the new one,
    /// which is safe under `foreign_keys = ON`: SQLite checks immediate
    /// constraints at the end of the statement, by which time the same id is
    /// back in the table.
    static func applyPulled(
        _ row: JSONRow,
        table: String,
        columns: Set<String>,
        in db: Database
    ) throws -> Bool {
        guard let id = row["id"]?.text else { return false }
        guard let incomingUpdatedAt = row["updated_at"]?.intValue else { return false }

        let local = try Row.fetchOne(
            db,
            sql: "SELECT updated_at, dirty FROM \(table) WHERE id = ?",
            arguments: [id])
        if let local {
            let localUpdatedAt: Int64 = local["updated_at"]
            let localDirty: Int64 = local["dirty"]
            if localDirty == 1 && localUpdatedAt > incomingUpdatedAt { return false }
        }

        // Unknown columns are dropped rather than failing the whole batch: the
        // server may run one migration ahead of this build.
        let names = row.keys.filter { columns.contains($0) && $0 != "dirty" }.sorted()
        if names.isEmpty { return false }
        let columnList = names.joined(separator: ", ")
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let values = names.map { databaseValue(from: row[$0] ?? .null) }

        try db.execute(
            sql: "INSERT OR REPLACE INTO \(table) (\(columnList), dirty) VALUES (\(placeholders), 0)",
            arguments: StatementArguments(values))
        return true
    }

    /// Stores the pull cursor and the time of this round trip.
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

    /// The column names of `table`.
    static func tableColumns(_ db: Database, table: String) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        var names: Set<String> = []
        for row in rows {
            let name: String = row["name"]
            names.insert(name)
        }
        return names
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
