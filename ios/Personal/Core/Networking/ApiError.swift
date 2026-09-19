import Foundation

/// One validation problem the server reports for one pushed row
/// (`422 validation_failed`; `gym-tracker.md` §4).
nonisolated struct FieldError: Codable, Equatable, Sendable {
    /// Table the row belongs to; empty when the server could not tell.
    var table: String
    /// Row id; empty when the server could not tell.
    var id: String
    /// Human-readable reason, in English.
    var message: String

    init(table: String, id: String, message: String) {
        self.table = table
        self.id = id
        self.message = message
    }
}

/// Every failure a request can end in.
///
/// The cases mirror the server's error codes one to one (spec §8) plus the two
/// failures that never reach the server: `network` and `decoding`. It is
/// `Equatable` so tests can compare an outcome without unwrapping, and
/// `nonisolated` because it travels from the sync actor to the main actor.
nonisolated enum ApiError: Error, Equatable, Sendable {
    /// 401 — the bearer token is missing, wrong or revoked.
    case unauthorized
    /// 404 — no such resource.
    case notFound
    /// 409 — another sync is writing; the request is safe to repeat.
    case conflict
    /// 413 — the push exceeded the server's row limit.
    case payloadTooLarge
    /// 415 — the upload's `Content-Type` is not an accepted image type.
    case unsupportedMediaType
    /// 422 — the server rejected the whole batch; rows stay dirty.
    case validation([FieldError])
    /// 400 and 5xx, carrying the server's message for the log.
    case server(String)
    /// The request never completed: offline, timeout, TLS.
    case network(String)
    /// A 2xx body that did not match the expected shape.
    case decoding

    /// The fixed English sentence screens show; raw server text is never
    /// surfaced (spec §8).
    var message: String {
        switch self {
        case .unauthorized:
            return "Check your API token in Settings"
        case .notFound:
            return "That item no longer exists on the server"
        case .conflict:
            return "Another sync was in progress. Try again"
        case .payloadTooLarge:
            return "Too much data to send at once"
        case .unsupportedMediaType:
            return "That image format is not supported"
        case .validation:
            return "The server rejected some changes"
        case .server:
            return "Something went wrong on the server"
        case .network:
            return "No connection. Changes are saved on this device"
        case .decoding:
            return "The server sent an unexpected response"
        }
    }
}
