import Foundation

/// One row on the wire: the table's columns keyed by their SQL names.
///
/// Rows are handled generically — the sync engine never spells a column out, it
/// copies whatever the table has. That way a new column in a later migration
/// needs no change here.
typealias JSONRow = [String: JSONValue]

/// The subset of JSON a sync row can hold: SQLite has no other storage classes
/// (blobs excluded — no table uses one).
///
/// Numbers decode to ``int`` when they are integral and fit `Int64`, and to
/// ``double`` otherwise, so `reps: 8` survives the round trip as `8` rather
/// than `8.0` — which matters because the server type-checks its columns.
nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Order matters: JSON `true` is not an `Int64`, and an integral number
        // must not be caught by the `Double` branch.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in a sync row")
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    /// The value as a whole number, accepting an integral `double` — the shape
    /// `updated_at` can arrive in from a JSON encoder that lost the type.
    var intValue: Int64? {
        switch self {
        case .int(let value):
            return value
        case .bool(let value):
            return value ? 1 : 0
        case .double(let value):
            guard value >= -9_007_199_254_740_992, value <= 9_007_199_254_740_992 else {
                return nil
            }
            return Int64(value)
        case .null, .string:
            return nil
        }
    }

    /// The value as text, or `nil` for every other case.
    var text: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

/// `POST /api/sync` request body (`gym-tracker.md` §5).
///
/// `push` is encoded in foreign-key order rather than in dictionary order, so
/// the bytes on the wire are deterministic and a parent table always precedes
/// its children — the server reads the batch in its own order, but a
/// reproducible body makes the request easy to assert on and to read in a log.
nonisolated struct SyncRequest: Encodable, Sendable {
    /// Cursor from the previous response; 0 on the first sync.
    var sinceSeq: Int64
    /// Dirty rows per table name.
    var push: [String: [JSONRow]]

    init(sinceSeq: Int64, push: [String: [JSONRow]]) {
        self.sinceSeq = sinceSeq
        self.push = push
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SyncRequestKey.self)
        try container.encode(sinceSeq, forKey: .sinceSeq)

        var pushContainer = container.nestedContainer(
            keyedBy: TableNameKey.self,
            forKey: .push)
        var written: Set<String> = []
        for table in SyncedTable.allCases {
            guard let rows = push[table.rawValue] else { continue }
            try pushContainer.encode(rows, forKey: TableNameKey(table.rawValue))
            written.insert(table.rawValue)
        }
        // Anything the engine put there that is not a known table still goes
        // out; the server answers 422 `unknown table` and the bug is visible.
        for name in push.keys.sorted() where written.contains(name) == false {
            try pushContainer.encode(push[name] ?? [], forKey: TableNameKey(name))
        }
    }
}

/// `POST /api/sync` response body.
nonisolated struct SyncResponse: Decodable, Sendable {
    /// The cursor to send next time.
    var seq: Int64
    /// `true` when the pull was truncated and the client must loop.
    var hasMore: Bool
    /// Changed rows per table name; every table is present, possibly empty.
    var pull: [String: [JSONRow]]

    init(seq: Int64, hasMore: Bool, pull: [String: [JSONRow]]) {
        self.seq = seq
        self.hasMore = hasMore
        self.pull = pull
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SyncResponseKey.self)
        self.seq = try container.decode(Int64.self, forKey: .seq)
        self.hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        self.pull = try container.decodeIfPresent(
            [String: [JSONRow]].self, forKey: .pull) ?? [:]
    }
}

/// Wire keys of ``SyncRequest``; snake_case as the server spells them.
private nonisolated enum SyncRequestKey: String, CodingKey {
    case sinceSeq = "since_seq"
    case push
}

/// Wire keys of ``SyncResponse``.
private nonisolated enum SyncResponseKey: String, CodingKey {
    case seq
    case hasMore = "has_more"
    case pull
}

/// A table name used as a JSON object key.
private nonisolated struct TableNameKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ name: String) {
        self.stringValue = name
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
