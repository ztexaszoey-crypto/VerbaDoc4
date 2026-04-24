import Foundation
import UserNotifications

// MARK: - DailyReminderService

final class DailyReminderService {
    static let shared = DailyReminderService()

    private let reminderIdentifier = "com.verbadoc4.daily.reminder"

    private init() {}

    func scheduleReminder(hour: Int = 9, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Time to Study! 📚"
        content.body = "Your flashcards are waiting. Keep your streak alive!"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}

// MARK: - SessionTracker

final class SessionTracker {
    static let shared = SessionTracker()

    private let sessionsKey = "com.verbadoc4.sessions"
    private init() {}

    func record(session: StudySession) {
        var sessions = loadSessions()
        sessions.append(session)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        sessions = sessions.filter { $0.date >= cutoff }
        saveSessions(sessions)
    }

    func loadSessions() -> [StudySession] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data)
        else { return [] }
        return decoded.map { $0.toStudySession() }
    }

    private func saveSessions(_ sessions: [StudySession]) {
        let records = sessions.map { SessionRecord(recording: $0) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}

// MARK: - SessionRecord (Codable proxy for StudySession)

private struct SessionRecord: Codable {
    let date: Date
    let cardsReviewed: Int
    let correctCount: Int
    let duration: TimeInterval

    init(recording session: StudySession) {
        self.date          = session.date
        self.cardsReviewed = session.cardsReviewed
        self.correctCount  = session.correctCount
        self.duration      = session.duration
    }

    func toStudySession() -> StudySession {
        StudySession(
            date: date,
            cardsReviewed: cardsReviewed,
            correctCount: correctCount,
            duration: duration
        )
    }
}
