import Foundation
import Combine

@MainActor
final class StreakManager: ObservableObject {
    @Published private(set) var currentStreak: Int = 0

    private let defaults: UserDefaults
    private let streakKey = "streak.current"
    private let lastStudyDateKey = "streak.lastStudyDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentStreak = defaults.integer(forKey: streakKey)
    }

    func markStudyCompleted(on date: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)

        guard let lastDate = defaults.object(forKey: lastStudyDateKey) as? Date else {
            currentStreak = 1
            persist(today)
            return
        }

        let lastDay = calendar.startOfDay(for: lastDate)
        if lastDay == today {
            return
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), lastDay == yesterday {
            currentStreak += 1
        } else {
            currentStreak = 1
        }

        persist(today)
    }

    func reset() {
        currentStreak = 0
        defaults.removeObject(forKey: streakKey)
        defaults.removeObject(forKey: lastStudyDateKey)
    }

    private func persist(_ date: Date) {
        defaults.set(currentStreak, forKey: streakKey)
        defaults.set(date, forKey: lastStudyDateKey)
    }
}
