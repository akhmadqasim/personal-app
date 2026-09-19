import Foundation

/// The app's only HTTP entry point.
///
/// An `actor` rather than a `@MainActor` type: the sync engine calls it from a
/// background actor and nothing it does belongs on the UI thread. The token is
/// read through a closure instead of being captured once, so replacing it in
/// Settings takes effect on the very next request without rebuilding anything.
actor APIClient {

    /// `https://api.akhmadqasim.com` in the app; a stub host in tests.
    let baseURL: URL

    private let tokenProvider: @Sendable () -> String?
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Requests

    /// `POST <path>` with a JSON body, decoding the JSON answer.
    func postJSON<T: Decodable & Sendable>(
        _ path: String,
        body: some Encodable & Sendable
    ) async throws -> T {
        var request = makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw ApiError.decoding
        }
        let (data, _) = try await send(request)
        return try decode(T.self, from: data)
    }

    /// `PUT <path>` with raw bytes — the exercise photo upload, which answers
    /// `{"image_key": "…"}`.
    func putBytes(
        _ path: String,
        data: Data,
        contentType: String
    ) async throws -> [String: String] {
        var request = makeRequest(path: path, method: "PUT")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, _) = try await send(request)
        return try decode([String: String].self, from: responseData)
    }

    /// `GET <path>` returning the raw bytes and the response `Content-Type` —
    /// the image download.
    func getData(_ path: String) async throws -> (Data, String?) {
        let request = makeRequest(path: path, method: "GET")
        let (data, response) = try await send(request)
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        return (data, contentType)
    }

    // MARK: - Plumbing

    private func makeRequest(path: String, method: String) -> URLRequest {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var request = URLRequest(url: baseURL.appending(path: relative))
        request.httpMethod = method
        request.timeoutInterval = 30
        if let token = tokenProvider(), token.isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Runs the request and turns anything but a 2xx into an ``ApiError``.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ApiError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ApiError.network("The response was not HTTP")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw mapFailure(status: http.statusCode, data: data)
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ApiError.decoding
        }
    }

    /// Maps the status code and the `{code, message, errors?}` body of a failed
    /// response onto ``ApiError`` (spec §8). The status is what decides: a body
    /// that is missing or unreadable only costs the message text.
    private func mapFailure(status: Int, data: Data) -> ApiError {
        let body = try? decoder.decode(ErrorBody.self, from: data)
        let message = body?.message ?? HTTPURLResponse.localizedString(forStatusCode: status)
        switch status {
        case 401:
            return .unauthorized
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 413:
            return .payloadTooLarge
        case 415:
            return .unsupportedMediaType
        case 422:
            return .validation(body?.errors ?? [])
        default:
            return .server(message)
        }
    }
}

/// The error envelope every endpoint uses (`gym-tracker.md` §4). File scope and
/// `nonisolated` so its synthesized `Decodable` conformance stays off the main
/// actor, where the client decodes it.
private nonisolated struct ErrorBody: Decodable {
    var code: String
    var message: String
    var errors: [FieldError]?
}
