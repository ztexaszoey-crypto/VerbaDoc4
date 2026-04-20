import Foundation
import SwiftData

@Model
final class StudyItem {
    var question:     String
    var answer:       String
    var explanation:  String
    var createdAt:    Date
    var nextReviewAt: Date
    var lastRating:   String
    var reps:         Int
    var intervalDays: Int
    var ease:         Double
    var documentTitle: String?

    init(question: String, answer: String, explanation: String, documentTitle: String? = nil) {
        self.question      = question
        self.answer        = answer
        self.explanation   = explanation
        self.documentTitle = documentTitle
        self.createdAt     = Date()
        self.nextReviewAt  = Date()
        self.lastRating    = "new"
        self.reps          = 0
        self.intervalDays  = 0
        self.ease          = 2.4
    }

    var isDueNow: Bool { nextReviewAt <= Date() }
}
