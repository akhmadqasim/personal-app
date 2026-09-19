import Foundation
import Security

/// A `SecItem*` call that failed, carrying the raw `OSStatus` for the log.
nonisolated struct KeychainError: Error, Equatable {
    var status: OSStatus
}

/// The bearer token store.
///
/// A plain `enum` over `SecItem*`: one account, no caching, no state. The
/// keychain survives a reinstall of the app only when iCloud restores it, which
/// is the behaviour we want — the token is typed once in Settings.
///
/// `nonisolated`: the Security framework is thread-safe and the sync actor
/// reads the token from its own executor on every request.
nonisolated enum Keychain {

    /// Keychain service, matching the bundle id.
    static let service = "com.akhmadqasim.personal"
    /// The single account this app stores.
    static let account = "api_token"

    /// The stored token, or `nil` when none was saved or the device is locked
    /// and has never been unlocked since boot.
    static func token() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the stored token. Deleting first keeps the accessibility
    /// attribute correct even when an older build wrote a different one.
    static func setToken(_ token: String) throws {
        deleteToken()
        var query = baseQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Forgets the token. Missing is success: the caller wants it gone.
    static func deleteToken() {
        _ = SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
