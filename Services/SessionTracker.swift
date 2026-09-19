import Foundation

final class SessionTracker {
    static let shared = SessionTracker()
    private init() {}

    private let key = "verba.recentSessions"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Codable wrapper

    private struct CodableSession: Codable {
        let date: Date
        let cardsReviewed: Int
        let correctCount: Int
        let duration: TimeInterval
    }

    func record(session: StudySession) {
        var all = loadAll()
        let cs = CodableSession(
            date: session.date,
            cardsReviewed: session.cardsReviewed,
            correctCount: session.correctCount,
            duration: session.duration
        )
        all.append(cs)

        // Keep only last 90 days
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        all = all.filter { $0.date >= cutoff }

        if let data = try? encoder.encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var recentSessions: [StudySession] {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        return loadAll()
            .filter { $0.date >= cutoff }
            .map { cs in
                StudySession(
                    date: cs.date,
                    cardsReviewed: cs.cardsReviewed,
                    correctCount: cs.correctCount,
                    duration: cs.duration
                )
            }
    }

    private func loadAll() -> [CodableSession] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let sessions = try? decoder.decode([CodableSession].self, from: data)
        else { return [] }
        return sessions
    }
}
