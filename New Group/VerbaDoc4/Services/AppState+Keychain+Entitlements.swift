import Foundation
import SwiftUI
import Security

@MainActor
final class AppState: ObservableObject {
    static let hasOnboardedKey = "hasOnboarded"
    static let premiumRedeemCode = "VERBADOC4FREE"

    @Published var hasPremium: Bool = false
    @Published var onboardingCompleted: Bool

    private let premiumService = "com.zoey.verbadoc4.premium"
    private let premiumAccount = "premium_status"

    init() {
        onboardingCompleted = UserDefaults.standard.bool(forKey: Self.hasOnboardedKey)
        hasPremium = (try? KeychainStore.loadString(service: premiumService, account: premiumAccount)) == "true" || EntitlementsChecker.hasPremiumEntitlement
    }

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: Self.hasOnboardedKey)
    }

    @discardableResult
    func redeem(code: String) -> Bool {
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard normalized == Self.premiumRedeemCode else { return false }
        unlockPremium()
        return true
    }

    func unlockPremium() {
        hasPremium = true
        try? KeychainStore.saveString("true", service: premiumService, account: premiumAccount)
    }
}

enum KeychainStore {
    static func saveString(_ value: String, service: String, account: String) throws {
        let encoded = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: encoded
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func loadString(service: String, account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return value
    }
}

enum EntitlementsChecker {
    static var hasPremiumEntitlement: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "VerbaDocPremiumEnabled") as? Bool) ?? false
    }
}
