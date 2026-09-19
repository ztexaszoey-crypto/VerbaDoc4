import Foundation
import Combine

final class StreakManager: ObservableObject {
    @Published private(set) var currentStreak: Int
    @Published private(set) var todayStudied: Bool
    @Published private(set) var totalStudyDays: Int

    private let streakKey      = "verba.streak.current"
    private let lastStudyKey   = "verba.streak.lastStudyDate"
    private let totalDaysKey   = "verba.streak.totalDays"

    init() {
        let streak    = UserDefaults.standard.integer(forKey: "verba.streak.current")
        let totalDays = UserDefaults.standard.integer(forKey: "verba.streak.totalDays")
        let cal       = Calendar.current
        let today     = cal.startOfDay(for: Date())

        var studied = false
        if let last = UserDefaults.standard.object(forKey: "verba.streak.lastStudyDate") as? Date {
            studied = cal.startOfDay(for: last) == today
        }

        self.currentStreak  = streak
        self.todayStudied   = studied
        self.totalStudyDays = totalDays
    }

    func recordStudySession() {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        if let last = UserDefaults.standard.object(forKey: lastStudyKey) as? Date {
            let lastDay = cal.startOfDay(for: last)
            if lastDay == today {
                // Already recorded today
                return
            } else if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                      lastDay == yesterday {
                // Consecutive day — extend streak
                currentStreak += 1
            } else {
                // Streak broken
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        todayStudied = true
        totalStudyDays += 1

        UserDefaults.standard.set(currentStreak,  forKey: streakKey)
        UserDefaults.standard.set(Date(),         forKey: lastStudyKey)
        UserDefaults.standard.set(totalStudyDays, forKey: totalDaysKey)
    }
}
