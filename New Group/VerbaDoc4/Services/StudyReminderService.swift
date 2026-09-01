import Foundation
import UserNotifications

// MARK: - StudyReminderService
//
// Intelligent reminder system driven by the SRS schedule, not a fixed clock.
// Replaces dumb "time to study!" alarms with contextual messages that tell
// the user WHY they should open the app.
//
// Notification strategy:
//   Morning check-in (8:00 AM): surfaces due count and slipping count
//   Evening recovery (7:30 PM): fires ONLY if user hasn't studied today
//   Streak-at-risk (2 hours before midnight): fires if streak > 2 and no study
//
// Content is computed at schedule time. The system reads UserDefaults for
// cached card state — no SwiftData access needed at notification time.

final class StudyReminderService {
    static let shared = StudyReminderService()

    private let center = UNUserNotificationCenter.current()
    private let morningID  = "study.morning"
    private let eveningID  = "study.evening"
    private let streakID   = "study.streak"

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Schedule (call after every study session and on app foreground)
    //
    // Passes card stats so notifications have real context.

    func scheduleAll(dueCount: Int, slippingCount: Int, streakDays: Int, todayStudied: Bool) {
        cancelAll()

        scheduleMorning(dueCount: dueCount, slippingCount: slippingCount)

        if !todayStudied {
            scheduleEvening(dueCount: dueCount, slippingCount: slippingCount)
            if streakDays >= 2 {
                scheduleStreakAlert(streakDays: streakDays)
            }
        }
    }

    // MARK: - Morning (8:00 AM daily)

    private func scheduleMorning(dueCount: Int, slippingCount: Int) {
        guard dueCount > 0 || slippingCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        if slippingCount >= 5 {
            content.title = "Memory is slipping."
            content.body  = "\(slippingCount) concepts need a quick reinforcement session. ~\(max(1, slippingCount / 3)) min."
        } else if dueCount > 0 {
            content.title = "\(dueCount) concept\(dueCount == 1 ? "" : "s") ready for review."
            content.body  = "Estimated \(max(1, dueCount / 3)) minute\(dueCount / 3 == 1 ? "" : "s"). Keep the streak alive."
        } else {
            content.title = "Good time to study."
            content.body  = "Your concepts are on track — lock in today's session."
        }

        var components = DateComponents()
        components.hour = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: morningID, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Evening recovery (7:30 PM, only if not studied)

    private func scheduleEvening(dueCount: Int, slippingCount: Int) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        if slippingCount > 0 {
            content.title = "\(slippingCount) concept\(slippingCount == 1 ? "" : "s") slipping away."
            content.body  = "4 minutes recovers them before tomorrow."
        } else if dueCount > 0 {
            content.title = "Today's review is waiting."
            content.body  = "\(dueCount) card\(dueCount == 1 ? "" : "s") scheduled for today. 5 minutes keeps your momentum."
        } else {
            content.title = "Quick session tonight?"
            content.body  = "Everything's on track — one more session locks it in."
        }

        var components = DateComponents()
        components.hour   = 19
        components.minute = 30

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Streak alert (10:00 PM, only if streak > 2 and no study)

    private func scheduleStreakAlert(streakDays: Int) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = "\(streakDays)-day streak at risk."
        content.body  = "Two minutes keeps it alive. You've earned it."

        var components = DateComponents()
        components.hour   = 22
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: streakID, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Cancel

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID, streakID])
    }

    func cancelEveningReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [eveningID, streakID])
    }
}

