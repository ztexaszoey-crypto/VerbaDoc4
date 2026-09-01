import Foundation

// MARK: - StudyScheduler
//
// THE single source of truth for all spaced repetition logic in VerbaDoc.
//
// Ownership contract (enforced by convention):
//   ONLY this file is allowed to mutate: mastery, stabilityDays, nextReviewAt,
//   reviewCount, lastReviewedAt, consecutiveMisses, cardLayer.
//
//   Every other file (VerbaFlowEngine, FlashcardStudyView, MasteryDecayService)
//   must call processAnswer() or applyDecay() — never manipulate card fields directly.
//
// Two public entry points:
//   processAnswer(card:correct:now:)  — called after a user answers a card
//   applyDecay(to:daysMissed:)        — called by MasteryDecayService on app foreground
//
// Memory model: Ebbinghaus forgetting curve (R = e^(-t/S))
//   S = stabilityDays — how many days before recall probability reaches ~37%
//   Correct answer → S doubles (capped at 180 days)
//   Wrong answer   → S halves (floored at 1 day)
//
// Exam compression:
//   ≤ 7 days  → cram mode   — interval = min(interval, daysToExam / 3)
//   ≤ 30 days → intensive   — interval = min(interval, daysToExam / 2)
//
// Layer multipliers (only on correct answers, never on misses):
//   active      → 1× base interval
//   maintenance → 2× base interval (cards stay at arm's length)
//   archived    → 4× base interval (rare sampling only)

enum StudyScheduler {

    // MARK: - Tuning Constants
    // All magic numbers live here — change one place, affects everything uniformly.

    static let stabilityGrowthFactor: Double = 2.0
    static let stabilityDecayFactor:  Double = 0.5
    static let maxStabilityDays:      Double = 180.0   // ~6 months
    static let minStabilityDays:      Double = 1.0     // floor: 1 day

    static let masteryGainOnCorrect:  Int = 10
    static let masteryLossOnWrong:    Int = 5

    static let promotionMasteryFloor: Int = 82   // active → maintenance threshold
    static let promotionReviewFloor:  Int = 4    // minimum reviews before promotion
    static let demotionMastery:       Int = 42   // maintenance/archived → active threshold

    // MARK: - Primary Entry Point 1: Answer Processing
    //
    // Call this immediately after a user answers a card. Handles everything:
    // mastery, stability, scheduling, layer transitions, review metadata.
    // VerbaFlowEngine and FlashcardStudyView are the only callers.

    // NOTE: After calling processAnswer, the CALLER is responsible for triggering
    // CloudSyncEngine.shared.enqueueStudyItemSync(id: card.id) to push the
    // updated card state to Firestore. The scheduler is intentionally context-free.
    static func processAnswer(card: StudyItem, correct: Bool, now: Date = Date()) {
        let examDate = card.document?.examDate

        // 1. Stability — must update before computing nextReviewAt
        card.stabilityDays = newStability(card.stabilityDays, correct: correct)

        // 2. Mastery — bounded [0, 100]
        card.mastery = max(0, min(100, card.mastery + (correct ? masteryGainOnCorrect : -masteryLossOnWrong)))

        // 3. Review metadata
        card.reviewCount       += 1
        card.lastReviewedAt     = now
        card.lastModified       = now   // keeps CloudSyncEngine's LWW cursor accurate
        card.consecutiveMisses  = correct ? 0 : card.consecutiveMisses + 1

        // 4. Next review date — uses the already-updated stability
        card.nextReviewAt = computeNextReview(
            stability: card.stabilityDays,
            correct:   correct,
            examDate:  examDate,
            layer:     card.cardLayer,
            from:      now
        )

        // 5. Layer transition — runs last so it sees the final mastery value
        applyLayerTransition(to: card)
    }

    // MARK: - Primary Entry Point 2: Passive Decay
    //
    // Call this once per calendar day (on app foreground) for ALL overdue cards.
    // daysMissed = calendar days since this function last ran.
    // Handles multi-day gaps correctly: applies e^(-daysMissed / S), not e^(-1/S) × n.
    // MasteryDecayService is the only caller.
    //
    // Returns the IDs of items that were actually mutated so the caller can enqueue
    // Firestore syncs. Without lastModified stamps, CloudSyncEngine's incremental
    // pull (whereField("lastModified", isGreaterThan: cutoff)) would never see decay.

    @discardableResult
    static func applyDecay(to items: [StudyItem], daysMissed: Int) -> [String] {
        guard daysMissed > 0 else { return [] }
        let now = Date()
        var modifiedIDs: [String] = []
        for item in items {
            guard item.reviewCount > 0,     // never decay cards the user hasn't seen
                  item.nextReviewAt < now   // only decay overdue cards
            else { continue }

            let r = retrievability(stability: item.stabilityDays, daysMissed: Double(daysMissed))
            let decayed = max(0, Int((Double(item.mastery) * r).rounded()))

            // Decay is lossy — never let this path raise mastery
            if decayed < item.mastery {
                item.mastery      = decayed
                item.lastModified = now   // stamp so CloudSyncEngine's LWW cursor sees this change
                applyLayerTransition(to: item)
                modifiedIDs.append(item.id)
            }
        }
        return modifiedIDs
    }

    // MARK: - Retrievability (public — used by ReadinessBreakdownView for display)
    //
    // R = e^(-t / S): probability of recall at t days since last review.

    static func retrievability(stability: Double, daysMissed: Double) -> Double {
        guard daysMissed > 0, stability > 0 else { return 1.0 }
        return exp(-daysMissed / max(stability, minStabilityDays))
    }

    // MARK: - Exam Intensity Label (UI helper)

    static func examIntensity(daysToExam: Int) -> String {
        switch daysToExam {
        case ...0:   return "exam day"
        case 1...7:  return "cram mode"
        case 8...30: return "intensive"
        default:     return "standard"
        }
    }

    // MARK: - Private: Stability

    private static func newStability(_ current: Double, correct: Bool) -> Double {
        let factor = correct ? stabilityGrowthFactor : stabilityDecayFactor
        return max(minStabilityDays, min(maxStabilityDays, current * factor))
    }

    // MARK: - Private: Next Review Date

    private static func computeNextReview(
        stability: Double,
        correct:   Bool,
        examDate:  Date?,
        layer:     String,
        from now:  Date
    ) -> Date {
        // Wrong answer: always review tomorrow, regardless of layer or exam pressure
        guard correct else {
            return Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        }

        // Base interval = stability days (time until R ≈ 37%)
        var interval = stability

        // Layer multiplier: maintenance and archived space out further
        // This means well-mastered cards need less frequent maintenance
        switch layer {
        case "maintenance": interval *= 2.0
        case "archived":    interval *= 4.0
        default:            break
        }

        // Exam compression: override spacing when the exam is close
        // Never lets interval collapse to zero — minimum 1 day always enforced below
        if let exam = examDate {
            let daysToExam = calendarDays(from: now, to: exam)
            if daysToExam > 0 && daysToExam <= 7 {
                interval = min(interval, max(1.0, Double(daysToExam) / 3.0))
            } else if daysToExam <= 30 {
                interval = min(interval, max(1.0, Double(daysToExam) / 2.0))
            }
        }

        let days = max(1, Int(interval.rounded()))
        return Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
    }

    // MARK: - Private: Layer Transitions

    private static func applyLayerTransition(to card: StudyItem) {
        switch card.cardLayer {
        case "active":
            // Promote to maintenance when mastery is high and the card is well-reviewed
            if card.mastery >= promotionMasteryFloor && card.reviewCount >= promotionReviewFloor {
                card.cardLayer = "maintenance"
            }
        case "maintenance", "archived":
            // Demote back to active if decay has pulled mastery below the safe threshold
            if card.mastery < demotionMastery {
                card.cardLayer = "active"
            }
        default:
            // Unknown layer — reset to active safely
            card.cardLayer = "active"
        }
    }

    // MARK: - Private: Date Math

    private static func calendarDays(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to:   Calendar.current.startOfDay(for: end)
        ).day ?? 0
    }
}

// MARK: - Backward-compatibility typealias
// Callers that haven't been updated yet can still compile.
// Remove this once all call sites use StudyScheduler directly.
typealias SRSScheduler = StudyScheduler
