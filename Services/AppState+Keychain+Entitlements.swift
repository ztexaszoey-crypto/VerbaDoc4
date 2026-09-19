import Foundation
import SwiftUI
import Combine

// MARK: - RedeemResult

enum RedeemResult {
    case success(String)
    case alreadyUnlocked
    case invalid
}

// MARK: - AppState

final class AppState: NSObject, ObservableObject {
    static let hasOnboardedKey = "hasOnboarded"

    @Published var onboardingCompleted: Bool
    @Published private(set) var unlockedEventItems: Set<String>

    /// Max 5 active event codes. Keys are normalized code strings, values are reward names.
    private static let eventCodes: [String: String] = [
        "FOUNDERS":  "Founders Badge",
        "EXAMWEEK":  "Exam Week Focus",
        "LAUNCH":    "Launch Edition",
        "BETA":      "Beta Tester",
        "WELCOME":   "Welcome Gift"
    ]

    private let unlocksKey = "unlocks.eventItems"

    override init() {
        onboardingCompleted = UserDefaults.standard.bool(forKey: Self.hasOnboardedKey)
        let stored = UserDefaults.standard.stringArray(forKey: "unlocks.eventItems") ?? []
        unlockedEventItems = Set(stored)
        super.init()
    }

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: Self.hasOnboardedKey)
    }

    @discardableResult
    func redeem(code: String) -> RedeemResult {
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let reward = Self.eventCodes[normalized] else { return .invalid }
        guard !unlockedEventItems.contains(reward) else { return .alreadyUnlocked }
        unlockedEventItems.insert(reward)
        UserDefaults.standard.set(Array(unlockedEventItems), forKey: unlocksKey)
        return .success(reward)
    }
}
