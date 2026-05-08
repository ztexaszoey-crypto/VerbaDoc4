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
        case .initiate:  return "Bronze"
        case .scholar:   return "Silver"
        case .analyst:   return "Gold"
        case .architect: return "Platinum"
        case .master:    return "Diamond"
        }
    }

    var color: Color {
        switch self {
        case .initiate:  return Color(red: 0.61, green: 0.39, blue: 0.23)
        case .scholar:   return Color(red: 0.74, green: 0.75, blue: 0.78)
        case .analyst:   return Color(red: 0.96, green: 0.78, blue: 0.24)
        case .architect: return Color(red: 0.65, green: 0.74, blue: 0.84)
        case .master:    return Color(red: 0.54, green: 0.82, blue: 0.96)
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
