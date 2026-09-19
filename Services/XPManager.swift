import SwiftUI
import Combine

// MARK: - Rank

enum Rank: Int, CaseIterable {
    case initiate  = 0
    case scholar   = 1
    case analyst   = 2
    case architect = 3
    case master    = 4

    var name: String {
        switch self {
        case .initiate:  return "Initiate"
        case .scholar:   return "Scholar"
        case .analyst:   return "Analyst"
        case .architect: return "Architect"
        case .master:    return "Master"
        }
    }

    var color: Color {
        switch self {
        case .initiate:  return VerbaTheme.muted
        case .scholar:   return VerbaTheme.green
        case .analyst:   return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .architect: return VerbaTheme.orange
        case .master:    return Color(red: 0.72, green: 0.18, blue: 0.92)
        }
    }

    var xpThreshold: Int {
        switch self {
        case .initiate:  return 0
        case .scholar:   return 100
        case .analyst:   return 500
        case .architect: return 1500
        case .master:    return 5000
        }
    }

    static func rank(for xp: Int) -> Rank {
        Rank.allCases.reversed().first { xp >= $0.xpThreshold } ?? .initiate
    }
}

// MARK: - XPManager

final class XPManager: ObservableObject {
    @Published private(set) var totalXP: Int

    private let xpKey = "verba.totalXP"
    private let lastLoginKey = "verba.lastLoginDate"
    private var previousRank: Rank

    enum XPEvent {
        case studySession
        case dailyLogin
        case streakMilestone

        var points: Int {
            switch self {
            case .studySession:     return 50
            case .dailyLogin:       return 10
            case .streakMilestone:  return 100
            }
        }
    }

    var currentRank: Rank {
        Rank.rank(for: totalXP)
    }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "verba.totalXP")
        self.totalXP = saved
        self.previousRank = Rank.rank(for: saved)
    }

    func award(_ event: XPEvent) {
        totalXP += event.points
        UserDefaults.standard.set(totalXP, forKey: xpKey)
    }

    func awardDailyLoginIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastData = UserDefaults.standard.object(forKey: lastLoginKey) as? Date {
            let lastDay = Calendar.current.startOfDay(for: lastData)
            if lastDay == today { return }
        }
        UserDefaults.standard.set(Date(), forKey: lastLoginKey)
        award(.dailyLogin)
    }

    func didRankUp() -> Rank? {
        let current = currentRank
        if current.rawValue > previousRank.rawValue {
            previousRank = current
            return current
        }
        return nil
    }

    func resetPreviousRank() {
        previousRank = currentRank
    }
}
