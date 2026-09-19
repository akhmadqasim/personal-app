import Foundation
import Synchronization
import Testing

@testable import Personal

// MARK: - The stub origin server
//
// Shared with `SyncEngineTests`. Every `StubServer` gets its own host, and the
// `URLProtocol` looks the instance up by that host, so suites running in
// parallel never see each other's traffic and no global mutable state is
// involved.

/// A scripted HTTP answer.
nonisolated struct StubResponse: Sendable {
    var status: Int
    var body: Data
    var contentType: String

    static func json(_ text: String, status: Int = 200) -> StubResponse {
        StubResponse(status: status, body: Data(text.utf8), contentType: "application/json")
    }
}

/// A request the stub saw, recorded in order.
nonisolated struct StubRequest: Sendable {
    var url: URL
    var method: String
    var headers: [String: String]
    var body: Data

    /// Header lookup that ignores case, the way HTTP does — the loading system
    /// is free to rewrite the capitalisation on its way out.
    func header(_ name: String) -> String? {
        for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame {
            return value
        }
        return nil
    }
}

/// Mutable innards of one ``StubServer``, guarded by a `Mutex`: the URL
/// loading system calls in on its own threads.
private nonisolated struct StubStorage {
    var scripted: [StubResponse] = []
    var seen: [StubRequest] = []
    var observer: (@Sendable (StubRequest) -> Void)?
}

/// A fake origin: answers scripted responses and records what it was asked.
nonisolated final class StubServer: Sendable {

    /// The base URL an `APIClient` has to be built with.
    let baseURL: URL

    private let storage = Mutex(StubStorage())

    init() {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        self.baseURL = URL(string: "https://\(host)")!
        StubRegistry.shared.register(self, host: host)
    }

    /// Queues one JSON answer. Answers are used in the order they were queued.
    func enqueue(_ json: String, status: Int = 200) {
        enqueue(StubResponse.json(json, status: status))
    }

    /// Queues one raw answer — bytes plus content type.
    func enqueue(_ response: StubResponse) {
        storage.withLock { $0.scripted.append(response) }
    }

    /// Runs `observer` on the loading thread for every request, before the
    /// answer is produced. Used to change the database while a sync is in
    /// flight.
    func observe(_ observer: @escaping @Sendable (StubRequest) -> Void) {
        storage.withLock { $0.observer = observer }
    }

    /// Everything the stub was asked, oldest first.
    var requests: [StubRequest] {
        storage.withLock { $0.seen }
    }

    /// Records the request and pops the next scripted answer. An empty script
    /// is a 500, so a run that makes more round trips than the test expects
    /// fails loudly instead of hanging.
    fileprivate func answer(_ request: StubRequest) -> StubResponse {
        let observer = storage.withLock { state -> (@Sendable (StubRequest) -> Void)? in
            state.seen.append(request)
            return state.observer
        }
        observer?(request)
        let scripted = storage.withLock { state -> StubResponse? in
            state.scripted.isEmpty ? nil : state.scripted.removeFirst()
        }
        if let scripted {
            return scripted
        }
        return StubResponse.json(#"{"code":"internal","message":"no scripted response"}"#, status: 500)
    }

    /// A session wired to this stub and to nothing else.
    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// Host → server. Tests are short-lived, so entries are never removed.
///
/// A singleton class rather than a namespace with a static `Mutex`: a `Mutex`
/// is non-copyable and lives happiest as an instance property.
private nonisolated final class StubRegistry: Sendable {
    static let shared = StubRegistry()

    private let servers = Mutex([String: StubServer]())

    func register(_ server: StubServer, host: String) {
        servers.withLock { $0[host] = server }
    }

    func server(for url: URL?) -> StubServer? {
        guard let host = url?.host() else { return nil }
        return servers.withLock { $0[host] }
    }
}

/// Answers every request aimed at a registered ``StubServer`` host.
nonisolated final class StubURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool {
        StubRegistry.shared.server(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let server = StubRegistry.shared.server(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let recorded = StubRequest(
            url: url,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request))
        let answer = server.answer(recorded)
        let response = HTTPURLResponse(
            url: url,
            statusCode: answer.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": answer.contentType])
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` hands a `URLProtocol` the body as a stream, so reading
    /// `httpBody` alone would see nothing on every POST.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0 ..< read])
        }
        return data
    }
}

// MARK: - Tests

/// An empty JSON body, for endpoints under test that ignore what they get.
private nonisolated struct EmptyBody: Encodable, Sendable {}

/// `GET /api/health` answers this.
private nonisolated struct Health: Decodable, Sendable {
    var ok: Bool
}

struct APIClientTests {

    private func makeClient(_ server: StubServer, token: String? = "secret-token") -> APIClient {
        APIClient(
            baseURL: server.baseURL,
            tokenProvider: { token },
            session: server.makeSession())
    }

    @Test func sendsTheBearerTokenAndHitsThePath() async throws {
        let server = StubServer()
        server.enqueue(#"{"ok":true}"#)
        let client = makeClient(server)

        let health: Health = try await client.postJSON("/api/health", body: EmptyBody())
        #expect(health.ok)

        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path() == "/api/health")
        #expect(request.header("Authorization") == "Bearer secret-token")
        #expect(request.header("Content-Type") == "application/json")
    }

    @Test func sendsNoAuthorizationHeaderWithoutAToken() async throws {
        let server = StubServer()
        server.enqueue(#"{"ok":true}"#)
        let client = makeClient(server, token: nil)

        let health: Health = try await client.postJSON("/api/health", body: EmptyBody())
        #expect(health.ok)

        let request = try #require(server.requests.first)
        let authorization = request.header("Authorization")
        #expect(authorization == nil)
    }

    @Test func mapsUnauthorized() async throws {
        let server = StubServer()
        server.enqueue(
            #"{"code":"unauthorized","message":"missing or invalid bearer token"}"#,
            status: 401)
        let client = makeClient(server)

        do {
            let _: Health = try await client.postJSON("/api/health", body: EmptyBody())
            Issue.record("the client accepted a 401")
        } catch let error as ApiError {
            #expect(error == ApiError.unauthorized)
        }
    }

    @Test func mapsValidationErrors() async throws {
        let server = StubServer()
        server.enqueue(
            #"""
            {"code":"validation_failed","message":"1 validation error(s)",
             "errors":[{"table":"workout_set","id":"s1","message":"reps must be >= 1"}]}
            """#,
            status: 422)
        let client = makeClient(server)

        do {
            let _: Health = try await client.postJSON("/api/sync", body: EmptyBody())
            Issue.record("the client accepted a 422")
        } catch let error as ApiError {
            let field = FieldError(table: "workout_set", id: "s1", message: "reps must be >= 1")
            #expect(error == ApiError.validation([field]))
            // Spec §5: the toast shows the first message, not a generic line.
            #expect(error.message == "reps must be >= 1")
        }
    }

    @Test func mapsTheOtherStatusCodes() async throws {
        let cases: [(Int, ApiError)] = [
            (404, ApiError.notFound),
            (409, ApiError.conflict),
            (413, ApiError.payloadTooLarge),
            (415, ApiError.unsupportedMediaType),
        ]
        for (status, expected) in cases {
            let server = StubServer()
            server.enqueue(#"{"code":"x","message":"nope"}"#, status: status)
            let client = makeClient(server)
            do {
                let _: Health = try await client.postJSON("/api/health", body: EmptyBody())
                Issue.record("the client accepted a \(status)")
            } catch let error as ApiError {
                #expect(error == expected)
            }
        }
    }

    @Test func mapsServerFailuresWithTheirMessage() async throws {
        let server = StubServer()
        server.enqueue(#"{"code":"internal","message":"internal error"}"#, status: 500)
        let client = makeClient(server)

        do {
            let _: Health = try await client.postJSON("/api/health", body: EmptyBody())
            Issue.record("the client accepted a 500")
        } catch let error as ApiError {
            #expect(error == ApiError.server("internal error"))
        }
    }

    @Test func reportsAnUnexpectedBodyAsDecoding() async throws {
        let server = StubServer()
        server.enqueue(#"{"unexpected":1}"#)
        let client = makeClient(server)

        do {
            let _: Health = try await client.postJSON("/api/health", body: EmptyBody())
            Issue.record("the client accepted a body of the wrong shape")
        } catch let error as ApiError {
            #expect(error == ApiError.decoding)
        }
    }

    @Test func putsRawBytesWithTheGivenContentType() async throws {
        let server = StubServer()
        server.enqueue(#"{"image_key":"exercises/e1.jpg"}"#)
        let client = makeClient(server)

        let result = try await client.putBytes(
            "/api/gym/exercises/e1/image",
            data: Data([0xFF, 0xD8, 0xFF]),
            contentType: "image/jpeg")
        #expect(result["image_key"] == "exercises/e1.jpg")

        let request = try #require(server.requests.first)
        #expect(request.method == "PUT")
        #expect(request.header("Content-Type") == "image/jpeg")
        #expect(request.body.count == 3)
    }

    @Test func getsRawBytesAndTheContentType() async throws {
        let server = StubServer()
        server.enqueue(
            StubResponse(status: 200, body: Data([0x89, 0x50]), contentType: "image/png"))
        let client = makeClient(server)

        let (data, contentType) = try await client.getData("/api/gym/images/e1")
        #expect(data.count == 2)
        #expect(contentType == "image/png")
    }
}
