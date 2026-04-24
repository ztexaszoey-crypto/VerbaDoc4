import Foundation

enum XPSystem {
    static let cardReviewXP: Int = 10
    static let streakBonusXP: Int = 5

    static func xpForAction(_ action: XPAction) -> Int {
        switch action {
        case .reviewCard: return cardReviewXP
        case .streakBonus: return streakBonusXP
        }
    }
}

enum XPAction {
    case reviewCard
    case streakBonus
}
