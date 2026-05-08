import Foundation
import Combine

@MainActor
final class XPManager: ObservableObject {
    @Published private(set) var totalXP: Int = 0

    private let xpKey = "xp.total"
    private let lastLoginKey = "xp.lastLoginDate"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        totalXP = defaults.integer(forKey: xpKey)
    }

    var currentRank: Rank {
        Rank.rank(for: totalXP)
    }

    func award(_ action: XPAction) {
        award(points: XPSystem.xpForAction(action))
    }

    func award(points: Int) {
        totalXP += points
        defaults.set(totalXP, forKey: xpKey)
    }

    /// Awards daily login XP once per calendar day.
    func awardDailyLoginIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = defaults.object(forKey: lastLoginKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }
        award(.dailyLogin)
        defaults.set(today, forKey: lastLoginKey)
    }

    func reset() {
        totalXP = 0
        defaults.removeObject(forKey: xpKey)
        defaults.removeObject(forKey: lastLoginKey)
    }
}
