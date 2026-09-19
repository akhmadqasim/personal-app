import Foundation

/// Where the bearer token lives, behind a protocol.
///
/// The app stores it in the keychain; tests swap in an in-memory double so the
/// Settings screen's save path can be exercised without touching the real
/// keychain, which a simulator test run shares with every other test.
///
/// The requirements are `nonisolated` for the same reason ``AppClock``'s are:
/// ``APIClient`` reads the token from its own executor on every request, far
/// from the main actor.
protocol TokenStore: Sendable {
    /// The stored token, or `nil` when none was saved.
    nonisolated func token() -> String?
    /// Replaces the stored token.
    nonisolated func setToken(_ token: String) throws
    /// Forgets the token.
    nonisolated func deleteToken()
}

/// The shipping store: ``Keychain``, one method deep.
nonisolated struct KeychainTokenStore: TokenStore {

    init() {}

    func token() -> String? {
        Keychain.token()
    }

    func setToken(_ token: String) throws {
        try Keychain.setToken(token)
    }

    func deleteToken() {
        Keychain.deleteToken()
    }
}
