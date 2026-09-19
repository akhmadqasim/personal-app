import Foundation
import GRDB
import Synchronization
import Testing

@testable import Personal

/// The fixed "now" every test starts from.
private let base: Int64 = 1_700_000_000_000

/// The push body as it arrived on the wire, decoded back.
///
/// Explicit `CodingKeys` rather than a snake-case decoding strategy: the
/// strategy would also rewrite the table names, which are dictionary keys.
private nonisolated struct RecordedPush: Decodable {
    var sinceSeq: Int64
    var push: [String: [JSONRow]]

    enum CodingKeys: String, CodingKey {
        case sinceSeq = "since_seq"
        case push
    }
}

/// A thread-safe tally, so a stub observer can act on the first request only.
///
/// A class, because `Mutex` is non-copyable and only a stored property can be
/// captured by the escaping observer closure.
private nonisolated final class Counter: Sendable {
    private let storage = Mutex(0)

    func increment() -> Int {
        storage.withLock { value in
            value += 1
            return value
        }
    }
}

/// Database, repository, stub and engine, all wired to the same clock.
private struct Stack {
    var database: DatabaseQueue
    var repository: GymRepository
    var clock: FixedClock
    var server: StubServer
    var engine: SyncEngine
}

private func makeStack(now: Int64 = base) throws -> Stack {
    let clock = FixedClock(now)
    let database = try AppDatabase.inMemory()
    let repository = GymRepository(dbWriter: database, clock: clock)
    let server = StubServer()
    let engine = SyncEngine(
        db: database,
        api: APIClient(
            baseURL: server.baseURL,
            tokenProvider: { "secret-token" },
            session: server.makeSession()),
        clock: clock)
    return Stack(
        database: database,
        repository: repository,
        clock: clock,
        server: server,
        engine: engine)
}

/// Pretends the row was already acknowledged by the server.
private func clearDirty(_ database: DatabaseQueue, table: String, id: String) throws {
    try database.write { db in
        try db.execute(
            sql: "UPDATE \(table) SET dirty = 0 WHERE id = ?",
            arguments: [id])
    }
}

private func decodePush(_ request: StubRequest) throws -> RecordedPush {
    try JSONDecoder().decode(RecordedPush.self, from: request.body)
}

private func bench(_ id: String = "e1", name: String = "Bench press") -> Exercise {
    Exercise(id: id, name: name, muscleGroup: .chest, equipment: .barbell)
}

/// One pulled exercise row, as the server would send it.
private func exerciseJSON(id: String, updatedAt: Int64, seq: Int64, name: String) -> String {
    """
    {"id":"\(id)","updated_at":\(updatedAt),"deleted_at":null,"seq":\(seq),
     "name":"\(name)","muscle_group":"chest","equipment":"barbell",
     "image_key":null,"notes":null}
    """
}

struct SyncEngineTests {

    // MARK: - Push

    @Test func pushesOnlyDirtyRowsAndDropsTheLocalColumns() async throws {
        let stack = try makeStack()
        try stack.repository.upsert(bench("e1"))
        try stack.repository.upsert(bench("e2", name: "Squat"))
        try clearDirty(stack.database, table: "exercise", id: "e2")

        stack.server.enqueue(#"{"seq":7,"has_more":false,"pull":{}}"#)
        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.success(pushed: 1, pulled: 0))

        let request = try #require(stack.server.requests.first)
        let body = try decodePush(request)
        #expect(body.sinceSeq == 0)

        let rows = body.push["exercise"] ?? []
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row["id"] == JSONValue.string("e1"))
        #expect(row["name"] == JSONValue.string("Bench press"))
        #expect(row["updated_at"] == JSONValue.int(base))
        #expect(row["deleted_at"] == JSONValue.null)
        // `dirty` is local-only and `seq` belongs to the server.
        #expect(row["dirty"] == nil)
        #expect(row["seq"] == nil)
        // A clean row never travels.
        #expect(body.push["program"] == nil)
    }

    @Test func chunksThePushInForeignKeyOrder() async throws {
        let stack = try makeStack()
        try seedBulk(stack.database, exercises: 400, sets: 150, now: base)

        stack.server.enqueue(#"{"seq":1,"has_more":false,"pull":{}}"#)
        stack.server.enqueue(#"{"seq":2,"has_more":false,"pull":{}}"#)
        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.success(pushed: 551, pulled: 0))

        let requests = stack.server.requests
        #expect(requests.count == 2)
        try #require(requests.count == 2)

        // The budget is spent table by table in foreign-key order, so the
        // parents are all in the first chunk and only children spill over.
        let first = try decodePush(requests[0])
        #expect(first.push["exercise"]?.count == 400)
        #expect(first.push["workout_session"]?.count == 1)
        #expect(first.push["workout_set"]?.count == 99)

        let second = try decodePush(requests[1])
        #expect(second.push["exercise"] == nil)
        #expect(second.push["workout_session"] == nil)
        #expect(second.push["workout_set"]?.count == 51)
    }

    // MARK: - Pull (last writer wins)

    @Test func newerIncomingRowOverwritesTheLocalOne() async throws {
        let stack = try makeStack(now: 1_000)
        try stack.repository.upsert(bench("e1"))
        try clearDirty(stack.database, table: "exercise", id: "e1")

        let pulled = exerciseJSON(id: "e1", updatedAt: 2_000, seq: 9, name: "Bench press (server)")
        stack.server.enqueue(#"{"seq":9,"has_more":false,"pull":{"exercise":[\#(pulled)]}}"#)

        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.success(pushed: 0, pulled: 1))

        let stored = try #require(stack.repository.exercise(id: "e1"))
        #expect(stored.name == "Bench press (server)")
        #expect(stored.updatedAt == 2_000)
        #expect(stored.seq == 9)
        #expect(stored.dirty == false)
    }

    @Test func olderIncomingRowLosesAgainstADirtyLocalOne() async throws {
        let stack = try makeStack(now: 5_000)
        try stack.repository.upsert(bench("e1"))

        let pulled = exerciseJSON(id: "e1", updatedAt: 4_000, seq: 3, name: "Bench press (server)")
        stack.server.enqueue(#"{"seq":3,"has_more":false,"pull":{"exercise":[\#(pulled)]}}"#)

        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.success(pushed: 1, pulled: 0))

        let stored = try #require(stack.repository.exercise(id: "e1"))
        #expect(stored.name == "Bench press")
        #expect(stored.updatedAt == 5_000)
    }

    // MARK: - Clearing dirty

    @Test func clearsDirtyOnlyForRowsThatDidNotChangeMeanwhile() async throws {
        let stack = try makeStack(now: 1_000)
        try stack.repository.upsert(bench("e1"))
        try stack.repository.upsert(bench("e2", name: "Squat"))

        // One write lands while the first request is in flight: `e1` is dirty
        // again with a newer `updated_at` than the one that was pushed.
        let repository = stack.repository
        let clock = stack.clock
        let seen = Counter()
        stack.server.observe { _ in
            let isFirst = seen.increment() == 1
            guard isFirst else { return }
            clock.advance(by: 500)
            try? repository.upsert(Exercise(
                id: "e1",
                name: "Bench press (edited)",
                muscleGroup: .chest,
                equipment: .barbell))
        }

        stack.server.enqueue(#"{"seq":4,"has_more":false,"pull":{}}"#)
        // The second round trip fails, so the run stops with `e1` still dirty.
        stack.server.enqueue(#"{"code":"internal","message":"internal error"}"#, status: 500)

        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.failure(ApiError.server("internal error")))

        let edited = try #require(stack.repository.exercise(id: "e1"))
        let untouched = try #require(stack.repository.exercise(id: "e2"))
        #expect(edited.dirty)
        #expect(edited.updatedAt == 1_500)
        #expect(untouched.dirty == false)
    }

    // MARK: - Cursor

    @Test func followsTheCursorWhileTheServerReportsMore() async throws {
        let stack = try makeStack()
        let firstRow = exerciseJSON(id: "e1", updatedAt: 100, seq: 10, name: "Bench press")
        let secondRow = exerciseJSON(id: "e2", updatedAt: 200, seq: 20, name: "Squat")
        stack.server.enqueue(#"{"seq":10,"has_more":true,"pull":{"exercise":[\#(firstRow)]}}"#)
        stack.server.enqueue(#"{"seq":20,"has_more":false,"pull":{"exercise":[\#(secondRow)]}}"#)

        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.success(pushed: 0, pulled: 2))

        let requests = stack.server.requests
        #expect(requests.count == 2)
        try #require(requests.count == 2)
        let first = try decodePush(requests[0])
        let second = try decodePush(requests[1])
        #expect(first.sinceSeq == 0)
        #expect(second.sinceSeq == 10)

        let stored = try stack.repository.exercises()
        #expect(stored.count == 2)
    }

    @Test func storesTheCursorAndTheSyncTime() async throws {
        let stack = try makeStack()
        stack.server.enqueue(#"{"seq":42,"has_more":false,"pull":{}}"#)

        let outcome = await stack.engine.sync()
        #expect(outcome == SyncOutcome.success(pushed: 0, pulled: 0))

        let state = try Migrations.syncState(in: stack.database)
        #expect(state["since_seq"] == 42)
        #expect(state["last_synced_at"] == base)
    }
}

// MARK: - Bulk seeding

/// Writes `exercises` dirty exercises, one dirty session and `sets` dirty sets
/// in one transaction — enough rows to force the engine to chunk.
///
/// `now` is a parameter rather than the file's `base` so the closure captures
/// nothing but its own arguments.
private func seedBulk(_ database: DatabaseQueue, exercises: Int, sets: Int, now: Int64) throws {
    try database.write { db in
        for index in 0 ..< exercises {
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, updated_at, name, muscle_group, equipment, dirty)
                    VALUES (?, ?, ?, 'chest', 'barbell', 1)
                    """,
                arguments: ["e\(index)", now + Int64(index), "Exercise \(index)"])
        }
        try db.execute(
            sql: """
                INSERT INTO workout_session (id, updated_at, started_at, dirty)
                VALUES ('s1', ?, ?, 1)
                """,
            arguments: [now, now])
        for index in 0 ..< sets {
            try db.execute(
                sql: """
                    INSERT INTO workout_set
                      (id, updated_at, session_id, exercise_id, position, weight_kg, reps, completed, dirty)
                    VALUES (?, ?, 's1', 'e0', ?, 50.0, 8, 0, 1)
                    """,
                arguments: ["ws\(index)", now + Int64(index), index])
        }
    }
}
