import Foundation

enum XPSystem {
    static func xpForAction(_ action: XPAction) -> Int {
        switch action {
        case .summarizeDocument: return 10
        case .generateNotes:     return 15
        case .studySession:      return 20
        case .quizCompletion:    return 25
        case .dailyLogin:        return 5
        case .reviewCard:        return 10
        }
    }
}

enum XPAction {
    case summarizeDocument
    case generateNotes
    case studySession
    case quizCompletion
    case dailyLogin
    case reviewCard
}
