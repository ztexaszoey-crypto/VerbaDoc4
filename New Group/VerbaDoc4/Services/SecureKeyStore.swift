import Foundation
import Security

// MARK: - SecureKeyStore
//
// Keychain-backed storage for Groq API keys.
//
// Lifecycle
// ─────────
//  1. App launch → call SecureKeyStore.shared.seedIfNeeded()
//     Reads Secrets._bootstrapKeys (gitignored) and saves to Keychain once.
//  2. All subsequent key access → SecureKeyStore.shared.apiKeys (Keychain).
//  3. To rotate: call replaceKeys(_:) with the new set; invalidate old keys
//     in the Groq dashboard.
//
// Why Keychain?
// ─────────────
//  • Encrypted at rest with the device's Secure Enclave key.
//  • Survives app updates; wiped on device wipe or app delete.
//  • kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: inaccessible until
//    the user unlocks the device AND keys cannot migrate to another device
//    via backup.

final class SecureKeyStore {
    static let shared = SecureKeyStore()
    private init() {}

    private let keychainService = "com.verbadoc.groq"
    private let keychainAccount = "api_keys_v1"

    // MARK: - Seed (call once at launch)

    /// Syncs the Keychain from Secrets._bootstrapKeys on every launch.
    ///
    /// Behaviour:
    ///  • Empty Keychain + non-empty bootstrap → writes bootstrap keys to Keychain.
    ///  • Keychain already has keys + bootstrap has MORE keys → merges (union, no duplicates).
    ///  • Empty bootstrap → no-op (leaves existing Keychain keys alone).
    ///
    /// This means you can add a new key to _bootstrapKeys, rebuild, and it will
    /// be picked up automatically without clearing the Keychain first.
    func seedIfNeeded() {
        let bootstrap = Secrets._bootstrapKeys.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && (t.hasPrefix("gsk_") || t.hasPrefix("vd_"))
        }
        guard !bootstrap.isEmpty else { return }

        let existing = apiKeys
        if existing.isEmpty {
            // First run — write bootstrap keys directly.
            try? replaceKeys(bootstrap)
        } else {
            // Merge: add any bootstrap keys not already in Keychain.
            let existingSet = Set(existing)
            let newKeys = bootstrap.filter { !existingSet.contains($0) }
            guard !newKeys.isEmpty else { return }
            try? replaceKeys(existing + newKeys)
        }
    }

    // MARK: - Read

    /// All valid API keys from the Keychain. Returns [] if none are stored.
    var apiKeys: [String] {
        guard let data = load(),
              let keys = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        // Accept both Groq keys (gsk_...) and proxy app secrets (vd_...)
        return keys.filter { !$0.isEmpty && ($0.hasPrefix("gsk_") || $0.hasPrefix("vd_")) }
    }

    // MARK: - Write

    /// Replaces the stored key set atomically.
    func replaceKeys(_ keys: [String]) throws {
        let data = try JSONEncoder().encode(keys)
        save(data)
    }

    /// Wipes all stored keys from the Keychain.
    func clearKeys() { delete() }

    // MARK: - Keychain Primitives

    private func load() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    private func save(_ data: Data) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData]      = data
            // Accessible after first device unlock; does NOT migrate via iCloud backup.
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
