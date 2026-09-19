import Foundation
import SwiftData

// MARK: - StudySessionEntity
//
// Brief §21 + §22: persisted SwiftData counterpart to the lightweight
// `StudySession` value type in `Models/Models.swift`. Both exist on
// purpose:
//
//   • `StudySession` (struct) — used at the API surface of
//     SessionTracker.record(session:) and the StudySessionSummary
//     view. Immutable value type, easy to pass around.
//
//   • `StudySessionEntity` (@Model) — durable record stored in
//     SwiftData. Used by analytics dashboard + the "recent
//     sessions" list. Has a stable id so ReviewRecord rows can
//     foreign-key back to the session that produced them.
//
// The struct ↔ @Model mapping happens at SessionTracker.record()
// time (write through to both). Existing callers keep using the
// struct; the @Model is owned by analytics/retention flows.

// MARK: - Delete semantics (Brief §21)
//
// `document` carries `@Relationship(deleteRule: .cascade)` so a
// Document delete cascades StudySessions scoped to it.
// Apple canonical pattern (matching VerbaDoc's Topic pair):
// the PARENT'S collection side (Document.studySessions) declares
// `inverse: \StudySessionEntity.document`; the to-one child link
// here is plain `@Relationship` with only the delete rule. This
// keeps inverse-declaration SINGLE-SOURCE per pair and avoids
// SwiftData runtime schema-validation warnings when both sides
// redundantly declare the same inverse.
//
// `reviewRecords` declares `inverse: \ReviewRecord.studySession` so
// SwiftData treats the pair as a single bidirectional relationship.
// Default `.nullify` is correct: deleting a session nullifies the
// foreign-key in ReviewRecord but keeps retention analytics on
// disk (Brief §35 aggregation needs the records to outlive the
// session listing's 90-day pruning).
//
// `userProgress` is plain — UserProgress is a singleton, never
// deleted in normal flow. When account-deletion ships, the fix is
// to add `@Relationship(deleteRule: .cascade, inverse: \...?.) var
//  studySessions: [StudySessionEntity] = []` on UserProgress (or
//  `.nullify` if history is sacred) and drop this side to plain.

@Model
final class StudySessionEntity {
    @Attribute(.unique) var id: String = UUID().uuidString
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var cardsReviewed: Int = 0
    var correctCount: Int = 0
    var durationSeconds: Double = 0

    /// Brief §21: cascade keeps session data clean when users
    /// remove source Documents. Inverse declared on the parent's
    /// collection side only (Document.studySessions → \StudySessionEntity.document).
    @Relationship(deleteRule: .cascade) var document: Document? = nil
    @Relationship(inverse: \ReviewRecord.studySession) var reviewRecords: [ReviewRecord] = []
    var userProgress: UserProgress? = nil

    init(document: Document? = nil, startedAt: Date = Date()) {
        self.id = UUID().uuidString
        self.document = document
        self.startedAt = startedAt
        self.endedAt = startedAt
        self.cardsReviewed = 0
        self.correctCount = 0
        self.durationSeconds = 0
    }

    // MARK: - Aggregate-update contract (Brief §35)
    //
    // CALLER RESPONSIBILITY: every time a ReviewRecord is inserted
    // for a card reviewed inside THIS session, the caller (typically
    // FlashcardStudyView → StudyQueueManager.advance + the in-place
    // `processAnswer(...)` in StudyScheduler.swift) MUST also
    // increment UserProgress.lifetimeCardsReviewed, session.cardsReviewed,
    // and the matching correctCount totals:
    //
    //   session.cardsReviewed += 1
    //   if review.wasCorrect { session.correctCount += 1 }
    //   userProgress.lifetimeCardsReviewed += 1
    //   if review.wasCorrect { userProgress.lifetimeCorrectAnswers += 1 }
    //
    // A future PR can promote to a `ProgressRecorder` helper that
    // atomically inserts ReviewRecord + updates aggregates in a
    // single try-context-save. For now caller writes all four.
    // The Home tab reads the cached aggregates for D1/D7/D30
    // retention scoring; without caller-side updates these
    // aggregates stay stale.

    // MARK: - Derived

    var accuracy: Double {
        cardsReviewed > 0 ? Double(correctCount) / Double(cardsReviewed) : 0
    }

    /// Bridges to the lightweight `StudySession` value type for
    /// callers that already use it (SessionTracker, summary views).
    var toValueType: StudySession {
        StudySession(
            date: startedAt,
            cardsReviewed: cardsReviewed,
            correctCount: correctCount,
            duration: durationSeconds
        )
    }
}
