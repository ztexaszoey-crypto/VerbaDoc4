import Foundation

final class StreakManager {
    private let defaults: UserDefaults
    private let streakKey = "streak.count"
    private let lastStudyDateKey = "streak.lastStudyDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var currentStreak: Int {
        defaults.integer(forKey: streakKey)
    }

    func recordStudySession(on date: Date = Date()) {
        let calendar = Calendar.current
        let previousDate = defaults.object(forKey: lastStudyDateKey) as? Date

        let newStreak: Int
        if let previousDate {
            if calendar.isDate(previousDate, inSameDayAs: date) {
                newStreak = currentStreak
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: date), calendar.isDate(previousDate, inSameDayAs: yesterday) {
                newStreak = max(1, currentStreak + 1)
            } else {
                newStreak = 1
            }
        } else {
            newStreak = 1
        }

        defaults.set(newStreak, forKey: streakKey)
        defaults.set(date, forKey: lastStudyDateKey)
    }
}
