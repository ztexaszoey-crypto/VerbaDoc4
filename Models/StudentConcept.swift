import Foundation
import SwiftData

// MARK: - StudentConcept
//
// Misconception Mapping (DESIGN.md §3 + §4). One row per
// concept-per-user: the dynamic model of what a student knows.
// `masteryScore` is OWNED by MasteryEngine — no other caller writes
// it. `confidence` is a 0–1 moving average blended from self-rated
// confidence + performance signal.
//
// `recentErrors` is the short memory used by the misconception
// detector: most-recent misconception IDs, newest first, capped
// ~10. Evidence beyond that lives in append-only ReviewRecord rows.
//
// Naming contract: `conceptName` is the denormalized query/display
// key. It is written in init() from `concept?.name` so the two can't
// drift at creation time. If a Concept is later renamed, callers
// must update both — v1 accepts this (matches Topic.normalizedName
// being a creation-time snapshot).

@Model
final class StudentConcept {
    @Attribute(.unique) var id: String = UUID().uuidString

    /// Denormalized key for display + query resilience (matches the
    /// Topic.normalizedName pattern in the codebase).
    var conceptName: String = ""
    /// To-one Concept. Inverse declared on the owning collection
    /// side: `Concept.studentConcepts` (see Concept.swift). Keep the
    /// two names in sync via init().
    var concept: Concept? = nil

    // MARK: - Mastery state (MasteryEngine owns the math)
    var masteryScore: Double = 0          // 0–100
    var confidence: Double = 0            // 0–1
    var attempts: Int = 0
    var correctAttempts: Int = 0
    var consecutiveCorrect: Int = 0
    var consecutiveMisses: Int = 0
    var recentErrors: [String] = []
    var lastReviewed: Date? = nil

    init(conceptName: String, concept: Concept? = nil) {
        self.id = UUID().uuidString
        self.conceptName = concept?.name ?? conceptName
        self.concept = concept
        self.masteryScore = 0
        self.confidence = 0
        self.attempts = 0
        self.correctAttempts = 0
        self.consecutiveCorrect = 0
        self.consecutiveMisses = 0
        self.recentErrors = []
        self.lastReviewed = nil
    }

    // MARK: - Derived

    var accuracy: Double {
        attempts > 0 ? Double(correctAttempts) / Double(attempts) : 0
    }

    /// Feed the most recent error ID into the short memory.
    /// Newest-first, capped at 10.
    func rememberError(_ misconceptionID: String) {
        recentErrors.removeAll { $0 == misconceptionID }
        recentErrors.insert(misconceptionID, at: 0)
        if recentErrors.count > 10 {
            recentErrors = Array(recentErrors.prefix(10))
        }
    }
}
