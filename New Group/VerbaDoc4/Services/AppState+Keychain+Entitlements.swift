import Foundation
import Security
import Combine

final class AppState: ObservableObject {
    @Published var hasPremiumAccess = false
}

extension AppState {
    private var keychainService: String { "com.verbadoc4.appstate" }
    private var premiumAccount: String { "premium_access" }

    func refreshPremiumStatus() {
        hasPremiumAccess = loadPremiumFromKeychain()
    }

    func setPremiumAccess(_ enabled: Bool) {
        savePremiumToKeychain(enabled)
        hasPremiumAccess = enabled
    }

    func hasValidEntitlements() -> Bool {
        true
    }

    private func savePremiumToKeychain(_ enabled: Bool) {
        let value = enabled ? "1" : "0"
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: premiumAccount
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadPremiumFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: premiumAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return false
        }

        return value == "1"
    }
}
