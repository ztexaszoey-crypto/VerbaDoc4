import Foundation
import SwiftData

@Model
final class StudyItem: Identifiable {
    @Attribute(.unique) var id: String = UUID().uuidString
    var question: String
    var answer: String
    var mastery: Int = 0 // 0-100 scale
    var reviewCount: Int = 0
    var createdAt: Date
    var lastReviewedAt: Date?
    
    var document: Document?
    
    init(question: String, answer: String, document: Document? = nil) {
        self.question = question
        self.answer = answer
        self.document = document
        self.createdAt = Date()
    }
    
    // MARK: - Mastery Levels
    var masteryLevel: MasteryLevel {
        switch mastery {
        case 0..<20:
            return .learning
        case 20..<50:
            return .familiar
        case 50..<80:
            return .competent
        default:
            return .mastered
        }
    }
    
    enum MasteryLevel: String {
        case learning = "Learning"
        case familiar = "Familiar"
        case competent = "Competent"
        case mastered = "Mastered"
    }
}
