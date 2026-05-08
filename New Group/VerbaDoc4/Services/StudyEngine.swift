import Foundation

enum StudyFilter: String, CaseIterable, Identifiable {
    case due
    case all
    case weak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .due: return "Due"
        case .all: return "All"
        case .weak: return "Weak"
        }
    }
}

enum ReviewRating: String, CaseIterable, Identifiable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }
}

struct ReviewDay: Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

struct TopicMastery: Identifiable {
    let topic: String
    let mastery: Int
    let cardCount: Int

    var id: String { topic }
}

enum StudyEngine {
    static func items(for filter: StudyFilter, from items: [StudyItem], now: Date = Date()) -> [StudyItem] {
        switch filter {
        case .due:
            return items.filter { $0.nextReviewAt <= now }
        case .all:
            return items
        case .weak:
            return items.filter { mastery(for: $0, now: now) < 60 }
        }
    }

    static func mastery(for item: StudyItem, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let repScore = min(Double(item.reps) * 18, 42)
        let easeScore = max(0, min((item.ease - 1.3) / 1.7, 1)) * 38
        let ratingScore: Double
        switch item.lastRating {
        case "easy": ratingScore = 20
        case "good": ratingScore = 14
        case "hard": ratingScore = 8
        case "again": ratingScore = 0
        default: ratingScore = item.reps == 0 ? 6 : 10
        }

        let overdueDays = max(0, calendar.dateComponents([.day], from: item.nextReviewAt, to: now).day ?? 0)
        let decay = min(Double(overdueDays) * 6, 40)
        return Int(max(0, min(100, repScore + easeScore + ratingScore - decay)).rounded())
    }

    static func mastery(for document: Document, now: Date = Date()) -> Int {
        let items = document.studyItems ?? []
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0) { $0 + mastery(for: $1, now: now) }
        return total / items.count
    }

    static func weakTopics(from items: [StudyItem], now: Date = Date()) -> [TopicMastery] {
        let grouped = Dictionary(grouping: items, by: topic(for:))
        return grouped
            .map { topic, topicItems in
                let average = topicItems.reduce(0) { $0 + mastery(for: $1, now: now) } / max(topicItems.count, 1)
                return TopicMastery(topic: topic, mastery: average, cardCount: topicItems.count)
            }
            .filter { $0.mastery < 60 }
            .sorted {
                if $0.mastery == $1.mastery {
                    return $0.cardCount > $1.cardCount
                }
                return $0.mastery < $1.mastery
            }
    }

    static func topic(for item: StudyItem) -> String {
        if let title = item.documentTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        let source = item.question.replacingOccurrences(of: "____", with: "")
        let parts = source.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let phrase = parts.prefix(3).map(String.init).joined(separator: " ")
        return phrase.isEmpty ? "General" : phrase
    }

    static func reviewCalendar(from items: [StudyItem], days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> [ReviewDay] {
        let start = calendar.startOfDay(for: now)
        return (0..<days).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let count = items.filter { calendar.isDate($0.nextReviewAt, inSameDayAs: date) || (offset == 0 && $0.nextReviewAt <= now) }.count
            return ReviewDay(date: date, count: count)
        }
    }

    static func recommendedDailyCards(for items: [StudyItem], examDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let baseline = max(10, items.count / 5)
        guard let examDate else { return baseline }
        let days = max(1, calendar.dateComponents([.day], from: now, to: examDate).day ?? 1)
        if days <= 3 { return max(baseline, items.count) }
        if days <= 7 { return max(baseline, items.count / 2) }
        if days <= 14 { return max(baseline, items.count / 3) }
        return baseline
    }

    static func countdownText(to examDate: Date?, now: Date = Date()) -> String {
        guard let examDate else { return "Set your exam date to unlock a study plan." }
        let seconds = max(0, Int(examDate.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return "\(days)d \(hours)h remaining"
    }

    static func personalizedSchedule(for items: [StudyItem], examDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let dueCount = items.filter { $0.nextReviewAt <= now }.count
        let weakCount = items.filter { mastery(for: $0, now: now) < 60 }.count
        let target = recommendedDailyCards(for: items, examDate: examDate, now: now, calendar: calendar)

        var plan = [
            "Review \(max(dueCount, min(target, items.count))) cards due today.",
            weakCount > 0 ? "Spend 10 minutes on \(weakCount) weak cards before new material." : "Use extra time for a full-deck practice round."
        ]

        if let examDate {
            let days = max(1, calendar.dateComponents([.day], from: now, to: examDate).day ?? 1)
            if days <= 7 {
                plan.append("Increase intensity this week: two shorter sessions are better than one long cram.")
            } else {
                plan.append("Aim for one focused session each day to stay ahead of schedule.")
            }
        } else {
            plan.append("Add an exam date for a tighter countdown-based plan.")
        }

        return plan
    }

    static func predictedGrade(for items: [StudyItem], now: Date = Date()) -> Int {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0) { $0 + mastery(for: $1, now: now) }
        return total / items.count
    }

    static func apply(_ rating: ReviewRating, to item: StudyItem, now: Date = Date(), calendar: Calendar = .current) {
        let quality: Double
        switch rating {
        case .again:
            quality = 1
            item.reps = 0
            item.intervalDays = 0
            item.ease = max(1.3, item.ease - 0.2)
            item.nextReviewAt = now.addingTimeInterval(10 * 60)
        case .hard:
            quality = 3
            item.reps += 1
            item.ease = max(1.3, item.ease - 0.15)
            item.intervalDays = max(1, Int((Double(max(item.intervalDays, 1)) * 1.2).rounded()))
            item.nextReviewAt = calendar.date(byAdding: .day, value: item.intervalDays, to: now) ?? now
        case .good:
            quality = 4
            item.reps += 1
            item.ease = max(1.3, item.ease + 0.02)
            let nextInterval = item.intervalDays <= 0 ? 1 : max(2, Int((Double(item.intervalDays) * item.ease).rounded()))
            item.intervalDays = nextInterval
            item.nextReviewAt = calendar.date(byAdding: .day, value: nextInterval, to: now) ?? now
        case .easy:
            quality = 5
            item.reps += 1
            item.ease = min(3.0, item.ease + 0.12)
            let nextInterval = item.intervalDays <= 1 ? 4 : max(4, Int((Double(item.intervalDays) * (item.ease + 0.35)).rounded()))
            item.intervalDays = nextInterval
            item.nextReviewAt = calendar.date(byAdding: .day, value: nextInterval, to: now) ?? now
        }

        item.lastRating = rating.rawValue
        let sm2Adjustment = 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)
        item.ease = max(1.3, min(3.0, item.ease + sm2Adjustment))
    }
}
