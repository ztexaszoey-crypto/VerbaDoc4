import Foundation

// MARK: - StudyScheduler
//
// SM-2 spaced-repetition algorithm (SuperMemo 2, Wozniak 1987).
//
// This is the same algorithm that powered Anki for years and has the most
// empirical validation of any open SRS system.
//
// How it works:
//   - Each card has an interval I (days until next review) and an ease factor EF.
//   - EF starts at 2.5 and adjusts based on answer quality.
//   - On correct: interval grows by EF each cycle (1 → 6 → 6×EF → ...)
//   - On incorrect: interval resets to 1, EF drops, card restarts
//
// We map our binary correct/incorrect to SM-2's quality scale:
//   correct   → quality 4  (correct with some hesitation — conservative)
//   incorrect → quality 1  (incorrect, but remembered after seeing answer)
//
// EF floor is 1.3 (prevents interval from stagnating for very hard cards).
// EF ceiling is 3.0 (prevents interval from exploding for very easy cards).

enum StudyScheduler {

    // MARK: - Core

    static func processAnswer(item: StudyItem, correct: Bool) {
        let quality: Double = correct ? 4.0 : 1.0
        let now = Date()

        if correct {
            // Advance through SM-2 interval sequence
            let newInterval: Double
            switch item.reviewCount {
            case 0:  newInterval = 1.0
            case 1:  newInterval = 6.0
            default: newInterval = max(1.0, (item.stabilityDays * item.easeFactor).rounded())
            }
            item.stabilityDays    = newInterval
            item.consecutiveMisses = 0
            item.mastery          = min(100, item.mastery + masteryGain(for: item))
        } else {
            // Reset: restart interval sequence
            item.stabilityDays    = 1.0
            item.consecutiveMisses += 1
            item.mastery          = max(0, item.mastery - masteryLoss(for: item))
        }

        // Update ease factor — SM-2 formula
        let efDelta = 0.1 - (5.0 - quality) * (0.08 + (5.0 - quality) * 0.02)
        item.easeFactor = min(3.0, max(1.3, item.easeFactor + efDelta))

        item.reviewCount += 1
        item.nextReviewAt = now.addingTimeInterval(item.stabilityDays * 86400)
    }

    // MARK: - Mastery delta
    //
    // Mastery is a UX score (0–100), not part of SM-2 math.
    // It drives the "slipping" / "weak" visual signals in the UI.
    // Gain is smaller for easy cards (they're already solid).
    // Loss is smaller for very hard cards (don't punish already-struggling cards twice).

    private static func masteryGain(for item: StudyItem) -> Int {
        if item.mastery >= 80 { return 5  }   // already strong — marginal improvement
        if item.mastery >= 50 { return 10 }
        return 15                              // new/weak card — big gain on first correct
    }

    private static func masteryLoss(for item: StudyItem) -> Int {
        if item.consecutiveMisses >= 3 { return 10 }  // already struggling — soften penalty
        if item.mastery <= 20          { return 10 }
        return 20
    }

    // MARK: - Projected next review
    //
    // Used by ReturnIntent to predict when a card will hit 70% retention.
    // Returns the number of days from now until the card reaches that threshold,
    // based on current stabilityDays (our proxy for the Ebbinghaus S parameter).

    static func daysUntilForgetting(_ item: StudyItem, retentionThreshold: Double = 0.70) -> Double {
        // R(t) = e^(-t/S) at threshold → t = S × ln(1/threshold)
        let lnFactor = -log(retentionThreshold)   // ln(1/0.70) ≈ 0.3567
        return item.stabilityDays * lnFactor
    }
}
