import Foundation

// MARK: - MasteryEngine
//
// Misconception Mapping (DESIGN.md §4). The deterministic mastery
// algorithm. The AI NEVER writes mastery — this code does.
//
// Four fused signals:
//   accuracy     — correct raises, wrong lowers
//   difficulty   — harder questions move the needle more (1.0–2.0 clamp)
//   recency      — old mastery decays toward 0: pow(0.90, days/7) ≈ 46-day half-life
//   consistency  — streaks: correct streaks grow gains, repeated misses grow losses
//
// All values are doubles internally; `StudentConcept.masteryScore`
// is a Double (0–100). UI rounds for display.

enum MasteryEngine {

    // MARK: - Constants (tunable, centralised)

    static let maxMastery: Double = 100
    static let decayBase: Double = 0.90     // pow(0.90, days/7)
    static let decayPeriodDays: Double = 7
    static let correctGainBase: Double = 4.0
    static let wrongLossBase: Double = 6.0
    static let streakBonusFactor: Double = 0.15     // per consecutive correct (cap 5)
    static let repeatPenaltyFactor: Double = 0.35   // per consecutive miss (cap 5)
    static let difficultyClamp: ClosedRange<Double> = 1.0...2.0
    static let maxStreakBonus: Int = 5
    static let maxRepeatPenalty: Int = 5

    /// Self-rating 0–3 → confidence anchor.
    /// 0 = not collected → performance-only blend.
    static func selfRatedConfidence(_ raw: Int) -> Double {
        switch raw {
        case 0:  return 0.0    // none — blend falls back to performance
        case 1:  return 0.3
        case 2:  return 0.6
        default: return 0.9
        }
    }

    // MARK: - Core update

    /// Apply one answered question to a StudentConcept. Mutates the
    /// model (it's a SwiftData class) and returns an Outcome for the
    /// caller (UI feedback, misconception-detector signal).
    ///
    /// - Parameters:
    ///   - sc: the StudentConcept to update
    ///   - correct: was the answer right?
    ///   - difficulty: Concept.difficulty (1.0 baseline)
    ///   - selfRatedConfidence: 0 none / 1 low / 2 med / 3 high (0 = not collected)
    ///   - daysSinceLastReview: recency input; 0 if reviewed today
    @discardableResult
    static func apply(
        to sc: StudentConcept,
        correct: Bool,
        difficulty: Double = 1.0,
        selfRatedConfidence: Int = 0,
        daysSinceLastReview: Double = 0
    ) -> Outcome {
        // 1. Recency decay of stored mastery.
        let decay = pow(decayBase, max(0, daysSinceLastReview) / decayPeriodDays)
        let base = sc.masteryScore * decay

        // 2. Difficulty weight.
        let weight = min(max(difficulty, difficultyClamp.lowerBound), difficultyClamp.upperBound)

        // 3. Consistency multipliers.
        let streakBonus = 1.0 + streakBonusFactor * Double(min(sc.consecutiveCorrect, maxStreakBonus))
        let repeatPenalty = 1.0 + repeatPenaltyFactor * Double(min(sc.consecutiveMisses, maxRepeatPenalty))

        // 4. Accuracy delta.
        let delta: Double
        if correct {
            delta = correctGainBase * weight * streakBonus
            sc.consecutiveCorrect += 1
            sc.consecutiveMisses = 0
        } else {
            delta = -wrongLossBase * weight * repeatPenalty
            sc.consecutiveMisses += 1
            sc.consecutiveCorrect = 0
        }

        let newMastery = min(maxMastery, max(0, base + delta))
        sc.masteryScore = newMastery
        sc.attempts += 1
        if correct { sc.correctAttempts += 1 }
        sc.lastReviewed = Date()

        // 5. Confidence moving average.
        let performanceSignal = correct ? 0.85 : 0.25
        let rated = Self.selfRatedConfidence(selfRatedConfidence)
        let blend: Double = selfRatedConfidence == 0
            ? performanceSignal
            : 0.6 * performanceSignal + 0.4 * rated
        sc.confidence = min(1.0, max(0.0, 0.5 * sc.confidence + 0.5 * blend))

        // 6. Misconception signal — feeds DESIGN.md §5 detector.
        let signal: Double
        if correct {
            signal = 0
        } else if sc.consecutiveMisses <= 1 {
            signal = 0.35   // first miss — could be careless
        } else {
            signal = min(1.0, 0.35 + 0.2 * Double(sc.consecutiveMisses - 1))
        }

        return Outcome(
            mastery: newMastery,
            confidence: sc.confidence,
            consecutiveMisses: sc.consecutiveMisses,
            misconceptionSignal: signal
        )
    }

    // MARK: - Outcome

    struct Outcome {
        let mastery: Double
        let confidence: Double
        let consecutiveMisses: Int
        /// 0–1: how strongly this answer should feed the misconception
        /// detector. Near 1 when a wrong answer lands on a concept
        /// with prior misses.
        let misconceptionSignal: Double
    }
}
