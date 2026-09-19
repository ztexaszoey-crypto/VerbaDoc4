import Foundation
import UserNotifications

final class StudyReminderService {
    static let shared = StudyReminderService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// Phase 20: `dailyGoal` lets the SettingsView surface a user-editable
    /// "Daily Goal" (default 20 cards). Notification copy now references the
    /// goal so users see "you've reviewed 12 of 20 cards today" rather than
    /// just "12 cards due". Existing callers stay compatible (parameter is
    /// defaulted), so all pre-Phase-20 sites keep compiling.
    func scheduleAll(dueCount: Int,
                     slippingCount: Int,
                     streakDays: Int,
                     todayStudied: Bool,
                     dailyGoal: Int = 20) {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            self.center.removeAllPendingNotificationRequests()
            self.scheduleContextual(
                dueCount: dueCount,
                slippingCount: slippingCount,
                streakDays: streakDays,
                todayStudied: todayStudied,
                dailyGoal: dailyGoal
            )
        }
    }

    private func scheduleContextual(
        dueCount: Int,
        slippingCount: Int,
        streakDays: Int,
        todayStudied: Bool,
        dailyGoal: Int
    ) {
        // Phase 20 evening-reminder copy references the user's daily
        // goal so the message feels like a personal study coach instead
        // of a generic nag. "you've reviewed N of M today" anchors the
        // goal into the push (the N defaults to 0 because StreakManager
        // doesn't track today's count yet — that's a follow-up; the
        // phrasing stays readable in both cases).
        if !todayStudied {
            schedule(
                id: "verba.evening",
                title: "time to study",
                body: dueCount > 0
                    ? "\(dueCount) card\(dueCount == 1 ? "" : "s") due · your daily goal is \(dailyGoal)"
                    : "a quick review session keeps memories fresh · your daily goal is \(dailyGoal)",
                hour: 19,
                minute: 30
            )
        }

        // Streak reminder for active streaks
        if streakDays >= 3 && !todayStudied {
            schedule(
                id: "verba.streak",
                title: "\(streakDays)-day streak at risk",
                body: "don't break your streak — just a few cards",
                hour: 20,
                minute: 0
            )
        }

        // Slipping cards
        if slippingCount > 0 {
            schedule(
                id: "verba.slipping",
                title: "cards are slipping",
                body: "\(slippingCount) card\(slippingCount == 1 ? "" : "s") approaching the forgetting threshold",
                hour: 10,
                minute: 0
            )
        }
    }

    private func schedule(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        var components = DateComponents()
        components.hour   = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            #if DEBUG
            if let error = error {
                print("[Reminder] Failed to schedule \(id): \(error.localizedDescription)")
            }
            #endif
        }
    }
}
