import Foundation
import SwiftData

@Model
final class StudyItem {
    @Attribute(.unique) var id: String = UUID().uuidString
    var question: String = ""
    var answer: String = ""
    var topic: String = ""
    var topicRef: Topic? = nil
    var mastery: Int = 0
    var reviewCount: Int = 0
    var stabilityDays: Double = 1.0   // current interval in days (SM-2: I(n))
    var easeFactor: Double = 2.5      // SM-2 EF — how quickly interval grows
    var nextReviewAt: Date = Date()
    var consecutiveMisses: Int = 0
    var document: Document?

    init(question: String, answer: String) {
        self.id = UUID().uuidString
        self.question = question
        self.answer = answer
        self.topic = ""
        self.topicRef = nil
        self.mastery = 0
        self.reviewCount = 0
        self.stabilityDays = 1.0
        self.easeFactor = 2.5
        self.nextReviewAt = Date()
        self.consecutiveMisses = 0
    }
}
