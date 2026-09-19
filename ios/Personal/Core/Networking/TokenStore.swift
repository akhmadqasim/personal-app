import Foundation
import Synchronization

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

/// A store that keeps the token in memory and nowhere else.
///
/// Ships in the app target rather than the test bundle because `#Preview`s and
/// ``AppEnvironment/preview()`` need it too: a preview that read the real
/// keychain would quietly authenticate against the live API, and one that
/// wrote to it would leak into the device's shared store.
nonisolated final class InMemoryTokenStore: TokenStore {

    private let storage: Mutex<String?>

    init(_ token: String? = nil) {
        self.storage = Mutex(token)
    }

    func token() -> String? {
        storage.withLock { $0 }
    }

    func setToken(_ token: String) throws {
        storage.withLock { $0 = token }
    }

    func deleteToken() {
        storage.withLock { $0 = nil }
    }
}
