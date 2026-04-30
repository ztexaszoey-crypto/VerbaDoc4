import Foundation
import Combine

@MainActor
final class XPManager: ObservableObject {
    @Published private(set) var totalXP: Int = 0

    private let xpKey = "xp.total"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        totalXP = defaults.integer(forKey: xpKey)
    }

    func award(_ action: XPAction) {
        totalXP += XPSystem.xpForAction(action)
        defaults.set(totalXP, forKey: xpKey)
    }

    func reset() {
        totalXP = 0
        defaults.removeObject(forKey: xpKey)
    }
}
