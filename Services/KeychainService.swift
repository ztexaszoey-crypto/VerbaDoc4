import Foundation

// MARK: - KeychainService
//
// Thin wrapper around Security framework for storing small secrets.
// Holds the AI provider API key (Groq, currently — never store API keys
// in UserDefaults) and authentication tokens for Supabase.

enum KeychainService {

    enum Key: String {
        // AI provider API key (Groq). Legacy `anthropicApiKey` enum case
        // is preserved as a deprecated alias so any older build's Keychain
        // entry still resolves during a one-time migration on next launch.
        @available(*, deprecated, message: "Renamed to groqApiKey — Groq is the active AI provider. This case is kept for migration only.")
        case anthropicApiKey  = "com.verbadoc.anthropic.apikey"
        case groqApiKey       = "com.verbadoc.groq.apikey"
        case accessToken      = "com.verbadoc.auth.accessToken"
        case refreshToken     = "com.verbadoc.auth.refreshToken"
        case tokenExpiresAt   = "com.verbadoc.auth.tokenExpiresAt"
        // AI generation counter — persisted in Keychain so it survives app
        // reinstalls on the same device + Apple ID, preventing trivial bypass.
        case freeAIGenerations = "com.verbadoc.freeAIGenerations"
    }

    // MARK: - Write

    @discardableResult
    static func set(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrAccount:     key.rawValue,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData:       data
        ]

        // Delete existing item first (update via delete+add is simpler than SecItemUpdate)
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Read

    static func get(_ key: Key) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key.rawValue,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    // MARK: - Delete

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrAccount:  key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Date helpers (stored as ISO8601 strings)

    @discardableResult
    static func set(_ date: Date, for key: Key) -> Bool {
        set(ISO8601DateFormatter().string(from: date), for: key)
    }

    static func getDate(_ key: Key) -> Date? {
        guard let s = get(key) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    // MARK: - Convenience

    static func has(_ key: Key) -> Bool {
        get(key) != nil
    }
}
