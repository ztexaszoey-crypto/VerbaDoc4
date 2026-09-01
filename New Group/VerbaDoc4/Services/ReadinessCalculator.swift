import Foundation

// MARK: - ReadinessCalculator V2
//
// Replaces the simplistic `mastery - freshnessPenalty` heuristic with a
// rigorous, explainable score grounded in memory science.
//
// Algorithm:
//   For each card:
//     - Compute retrievability: R = e^(-daysSinceReview / stabilityDays)
//       (probability the student can recall this card right now)
//     - Compute weight: 1.0 + min(consecutiveMisses, 3) × 0.4
//       (persistently wrong cards count more toward the score)
//     - cardScore = R × (mastery / 100.0)
//
//   documentScore = weighted average of all cardScores × 100
//
//   examPressure modifier (applied last):
//     If exam is set and within 14 days, score is penalized by urgency
//     (a 75% readiness score when the exam is tomorrow is actually alarming)
//
// The result is a number in [0, 100] that reflects genuine recall readiness,
// not just "how many cards have been reviewed."
//
// DETERMINISTIC: given the same input state, always produces the same output.
// STABLE: small changes in a single card produce small score changes.

enum ReadinessCalculator {

    struct Result {
        /// 0–100 readiness score
        let score: Int
        /// Human label for the score
        let label: String
        /// Color key (maps to VerbaTheme colors in the UI)
        let colorKey: ReadinessColor
        /// Number of cards with low retrievability (< 0.5)
        let atRiskCount: Int
        /// Number of cards with consecutiveMisses ≥ 2
        let persistentlyWeakCount: Int
        /// Average retrievability across all cards (0–1)
        let avgRetrievability: Double
        /// Exam pressure description, nil if no exam or exam is far away
        let examPressureNote: String?
    }

    enum ReadinessColor {
        case green, yellow, orange, red
    }

    static func calculate(for items: [StudyItem], examDate: Date? = nil) -> Result {
        guard !items.isEmpty else {
            return Result(score: 0, label: "no cards yet", colorKey: .red,
                         atRiskCount: 0, persistentlyWeakCount: 0,
                         avgRetrievability: 0, examPressureNote: nil)
        }

        let now = Date()
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        var atRiskCount = 0
        var persistentlyWeakCount = 0

        for item in items {
            // Days since last review (0 if never reviewed)
            let daysSince: Double = {
                guard let reviewed = item.lastReviewedAt else { return 0 }
                return max(0, now.timeIntervalSince(reviewed) / 86_400)
            }()

            // Retrievability: R = e^(-t / S)
            let R: Double = {
                guard daysSince > 0, item.stabilityDays > 0 else { return 1.0 }
                return exp(-daysSince / item.stabilityDays)
            }()

            // Weight: persistently wrong cards matter more
            let weight = 1.0 + min(Double(item.consecutiveMisses), 3) * 0.4

            // Card score: retrievability × mastery fraction
            let cardScore = R * (Double(item.mastery) / 100.0)

            weightedSum += cardScore * weight
            totalWeight += weight

            if R < 0.5 { atRiskCount += 1 }
            if item.consecutiveMisses >= 2 { persistentlyWeakCount += 1 }
        }

        let avgRetrievability = totalWeight > 0 ? weightedSum / totalWeight : 0
        var rawScore = avgRetrievability * 100.0

        // Exam pressure modifier
        var examNote: String? = nil
        if let exam = examDate {
            let daysToExam = Calendar.current.dateComponents([.day], from: now, to: exam).day ?? 999
            if daysToExam >= 0 && daysToExam <= 14 {
                let urgencyPenalty: Double = {
                    switch daysToExam {
                    case 0:    return 0.25  // exam day: -25%
                    case 1...3: return 0.15 // 1-3 days: -15%
                    case 4...7: return 0.08 // 4-7 days: -8%
                    default:    return 0.04 // 8-14 days: -4%
                    }
                }()
                rawScore *= (1.0 - urgencyPenalty)
                switch daysToExam {
                case 0:     examNote = "exam today — every point matters"
                case 1:     examNote = "exam tomorrow — focus on weak spots"
                case 2...3: examNote = "exam in \(daysToExam) days — cram mode"
                case 4...7: examNote = "exam in \(daysToExam) days — intensive review"
                default:    examNote = "exam in \(daysToExam) days"
                }
            }
        }

        let score = max(0, min(100, Int(rawScore.rounded())))

        let label: String
        let colorKey: ReadinessColor
        switch score {
        case 85...:    label = "exam ready";    colorKey = .green
        case 65..<85:  label = "almost there";  colorKey = .yellow
        case 40..<65:  label = "building up";   colorKey = .orange
        default:       label = "just starting"; colorKey = .red
        }

        return Result(
            score: score,
            label: label,
            colorKey: colorKey,
            atRiskCount: atRiskCount,
            persistentlyWeakCount: persistentlyWeakCount,
            avgRetrievability: avgRetrievability,
            examPressureNote: examNote
        )
    }

    /// Quick score for library card display (no full Result needed)
    static func quickScore(for items: [StudyItem], examDate: Date? = nil) -> Int {
        calculate(for: items, examDate: examDate).score
    }
}
