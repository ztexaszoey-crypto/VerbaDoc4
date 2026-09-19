import Foundation
import SwiftData

// MARK: - ReviewRecord
//
// Brief §35: track retention-meaningful learning metrics. Each
// individual card answer produces a ReviewRecord.
//
// Per-card analytics surfaces
//   • Brief §12 stuck-card detection — `consecutiveMisses` derived
//     from the most-recent N records per StudyItem. ≥3 in a row =
//     "stuck". This entity is the source of truth for that signal.
//   • Brief §11 weak-topic detection — Topic.weakRatio can derive
//     from the most-recent (Miss, Topic) pair rather than from a
//     precomputed integer on StudyItem.
//
// Delete rules
//   • StudyItem → .nullify: deleting a StudyItem does NOT purge
//     its review history (we want retention analytics to survive
//     individual-card deletion).
//   • StudySessionEntity → .nullify (via inverse on StudySessionEntity.reviewRecords):
//     deleting a session does NOT purge its review records (so
//     retention charts work even after session-list pruning).
//
// Storage strategy
//   • Records are append-only. No fields are mutated after insert.
//   • For each StudyItem, only the most-recent ~20 records are
//     ever read by the stuck-card detector. Older records remain
//     on disk for long-term retention but are not surfaced in UI.
//   • Brief §21 "don't leave orphaned records" — the `.nullify`
//     rules already accommodate this. No cascade needed.

// MARK: - Aggregate-update contract (Brief §35)
//
// CALLER RESPONSIBILITY: every time this ReviewRecord is inserted
// (typically via FlashcardStudyView during answer → reveal), the
// caller MUST also update the corresponding aggregates so the
// Home tab and analytics dashboard stay coherent:
//
//   userProgress.lifetimeCardsReviewed += 1
//   if wasCorrect { userProgress.lifetimeCorrectAnswers += 1 }
//
//   if let session = studySession {
//       session.cardsReviewed += 1
//       if wasCorrect { session.correctCount += 1 }
//   }
//
// Future PR can promote these aggregates into SwiftData observation
// helpers that auto-update via modelContext.processPendingChanges
// notifications. For now: caller writes all four, just like StudyQueueManager.
// advance + the in-place `processAnswer(...)` call already maintains
// StudyItem.mastery / consecutiveMisses inline.

@Model
final class ReviewRecord {
    @Attribute(.unique) var id: String = UUID().uuidString
    var answeredAt: Date = Date()
    var wasCorrect: Bool = false
    /// 0=none / 1=low / 2=med / 3=high. Default 0 means the UI
    /// never collected a self-confidence rating.
    var confidenceRaw: Int = 0
    /// Time spent answering this card. 0 means unrecorded.
    var durationMs: Int = 0
    /// DrillScope raw value: "all" / "weak" / "due" / "new" /
    /// "document:<id>" — fine as a string blob for now.
    var drillScope: String = "all"

    var studyItem: StudyItem? = nil
    var studySession: StudySessionEntity? = nil

    init(
        studyItem: StudyItem? = nil,
        studySession: StudySessionEntity? = nil,
        wasCorrect: Bool,
        confidenceRaw: Int = 0,
        durationMs: Int = 0,
        drillScope: String = "all"
    ) {
        self.id = UUID().uuidString
        self.studyItem = studyItem
        self.studySession = studySession
        self.wasCorrect = wasCorrect
        self.confidenceRaw = confidenceRaw
        self.durationMs = durationMs
        self.drillScope = drillScope
    }
}
