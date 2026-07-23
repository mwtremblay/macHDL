import Foundation
import Security

/// Minimal generic-password Keychain wrapper -- this app's first stored
/// credential is the TMDB API key (TVEpisodeMetadataFetcher/SettingsView),
/// but written generically (service+account -> value) rather than
/// TMDB-specific in case a future credential needs the same thing. No
/// third-party dependency; the Security framework's C API is small enough
/// not to warrant one.
enum KeychainStore {
    enum StoreError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
                return "Keychain operation failed: \(message) (\(status))"
            }
        }
    }

    /// Overwrites any existing value for this service/account -- callers
    /// don't need to check-then-update themselves.
    static func set(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw StoreError.unexpectedStatus(updateStatus)
        }
    }

    /// nil for "nothing stored" (errSecItemNotFound), same "absence isn't an
    /// error" treatment as this app's other "nothing installed yet" reads
    /// (e.g. SMSMediaService.listVideos on a partition that doesn't exist).
    static func get(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// A no-op (not an error) if nothing was stored -- matches `set`'s own
    /// "overwrite or create" symmetry.
    static func delete(service: String, account: String) {
        let query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
