import SwiftUI

// MARK: - Rank

enum Rank: Int, CaseIterable, Equatable {
    case initiate  = 0
    case scholar   = 1
    case analyst   = 2
    case architect = 3
    case master    = 4

    static let xpPerRank = 500

    var minXP: Int { rawValue * Self.xpPerRank }
    var maxXP: Int { (rawValue + 1) * Self.xpPerRank }

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
        case .initiate:  return Color(red: 0.20, green: 0.82, blue: 0.90)
        case .scholar:   return Color(red: 0.35, green: 0.76, blue: 0.57)
        case .analyst:   return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .architect: return Color(red: 1.00, green: 0.78, blue: 0.15)
        case .master:    return Color(red: 0.70, green: 0.40, blue: 0.95)
        }
    }

    var isMax: Bool { self == .master }

    static func rank(for xp: Int) -> Rank {
        let clamped = max(0, xp)
        let index = min(clamped / xpPerRank, Rank.allCases.count - 1)
        return Rank(rawValue: index) ?? .master
    }

    func xpProgress(totalXP: Int) -> Double {
        guard !isMax else { return 1.0 }
        let progress = totalXP - minXP
        let range = maxXP - minXP
        return min(max(Double(progress) / Double(range), 0), 1)
    }
}
