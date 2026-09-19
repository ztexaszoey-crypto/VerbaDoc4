import Foundation

enum ReadinessCalculator {
    enum ColorKey { case green, yellow, orange, red }

    struct Result {
        let score: Int
        let label: String
        let colorKey: ColorKey
    }

    static func quickScore(for items: [StudyItem], examDate: Date?) -> Int {
        guard !items.isEmpty else { return 0 }

        let now = Date()
        let avgMastery = Double(items.map(\.mastery).reduce(0, +)) / Double(items.count)

        // Penalise overdue cards
        let overdueCount = items.filter { $0.nextReviewAt < now }.count
        let overduePenalty = Double(overdueCount) / Double(items.count) * 20.0

        // Bonus for exam proximity preparedness
        var examBonus = 0.0
        if let exam = examDate {
            let daysLeft = exam.timeIntervalSince(now) / 86400
            if daysLeft > 0 && daysLeft < 14 && avgMastery > 70 {
                examBonus = 5.0
            }
        }

        let raw = avgMastery - overduePenalty + examBonus
        return max(0, min(100, Int(raw.rounded())))
    }

    static func calculate(for items: [StudyItem], examDate: Date?) -> Result {
        let score = quickScore(for: items, examDate: examDate)

        switch score {
        case 80...100:
            return Result(score: score, label: "ready",    colorKey: .green)
        case 55..<80:
            return Result(score: score, label: "building", colorKey: .yellow)
        case 30..<55:
            return Result(score: score, label: "shaky",    colorKey: .orange)
        default:
            return Result(score: score, label: "new",      colorKey: .red)
        }
    }
}
