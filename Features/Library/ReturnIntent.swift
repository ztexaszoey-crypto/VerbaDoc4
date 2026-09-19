import Foundation

// MARK: - ReturnIntent
//
// A structured prediction: "the user should return at this time, for this deck, because of this."
//
// Generated at session end from the Ebbinghaus forgetting curve applied to each
// studied card's stabilityDays. Stored in ReturnIntentStore and consumed by
// StudyDecision.resolve() — which is the only place priority decisions are made.
//
// The system is PREDICTIVE, not punitive. If the user misses the window, urgency
// downgrades — it never nags or guilts.

struct ReturnIntent: Codable {

    // MARK: - Fields

    let documentID:    String   // Document.id (UUID string)
    let documentTitle: String
    let cardCount:     Int      // cards that will be in the forgetting window
    let optimalReturnAt: Date   // center of the predicted forgetting window
    let windowHours:   Int      // how wide the window is (both sides)
    let riskScore:     Double   // 0–1: fraction of studied cards at risk in window
    let generatedAt:   Date

    // MARK: - Window logic

    private var windowEnd: Date {
        optimalReturnAt.addingTimeInterval(Double(windowHours) * 3600)
    }

    private var expiredCutoff: Date {
        // Beyond 3× the window duration, stop surfacing this intent.
        optimalReturnAt.addingTimeInterval(Double(windowHours) * 3600 * 3)
    }

    /// User is within the optimal study window right now.
    var isWithinWindow: Bool {
        let now = Date()
        return now >= optimalReturnAt && now <= windowEnd
    }

    /// Window has passed but not so long ago that we should forget about it.
    var isMissed: Bool {
        let now = Date()
        return now > windowEnd && now <= expiredCutoff
    }

    /// Intent is so old it's no longer relevant — fall back to NextStudyAction.
    var isExpired: Bool {
        Date() > expiredCutoff
    }

    /// True while this intent should influence the home screen.
    var isRelevant: Bool { !isExpired }

    /// How far away the window open is, if not yet open.
    var timeUntilWindow: TimeInterval {
        max(0, optimalReturnAt.timeIntervalSinceNow)
    }

    // MARK: - Display

    enum Urgency { case high, medium, low }

    var urgency: Urgency {
        if isWithinWindow && riskScore >= 0.4 { return .high }
        if isWithinWindow                      { return .medium }
        return .low
    }

    /// One-line headline consumed by StudyDecision display helpers.
    var headline: String {
        switch urgency {
        case .high:
            return "\(cardCount) card\(cardCount == 1 ? "" : "s") are slipping right now"
        case .medium:
            return "good time to review \(documentTitle)"
        case .low:
            if isMissed {
                return "\(cardCount) card\(cardCount == 1 ? "" : "s") have slipped"
            }
            let h = Int(timeUntilWindow / 3600)
            return h < 1 ? "review window opening soon" : "review opens in \(h)h"
        }
    }

    /// CTA button label consumed by StudyDecision display helpers.
    var ctaLabel: String {
        let mins = max(1, cardCount * 20 / 60)
        switch urgency {
        case .high:   return "review now · ~\(mins) min"
        case .medium: return "start review · ~\(mins) min"
        case .low:    return "catch up · ~\(mins) min"
        }
    }

    var isUrgent: Bool { urgency == .high }

    // MARK: - Generation

    /// Compute a ReturnIntent from a completed study session on a document.
    /// Returns nil if there are no reviewed cards to predict from.
    ///
    /// Math: Ebbinghaus forgetting curve R(t) = e^(-t/S)
    /// At R=0.70 (70% retention threshold): t = S × ln(1/0.70) ≈ S × 0.3567 days
    static func generate(for document: Document, studiedItems: [StudyItem]) -> ReturnIntent? {
        let items = studiedItems.filter { $0.reviewCount > 0 && $0.stabilityDays > 0 }
        guard !items.isEmpty else { return nil }

        let now = Date()

        // Forgetting curve: when does each card cross 70% retention?
        let ln_inv_07 = 0.35667  // ln(1/0.70), precomputed
        let forgettingTimes: [Date] = items
            .compactMap { item -> Date? in
                let daysToRisk = item.stabilityDays * ln_inv_07
                guard daysToRisk > 0 else { return nil }
                return now.addingTimeInterval(daysToRisk * 86400)
            }
            .sorted()

        guard !forgettingTimes.isEmpty else { return nil }

        // Pick the optimal return time: top-third index triggers when ~33% of
        // studied cards are approaching the forgetting threshold.
        let targetIndex = max(0, forgettingTimes.count / 3)
        let optimalReturn = forgettingTimes[targetIndex]

        // Count cards in the ±4-hour window around optimalReturn
        let windowRadius: TimeInterval = 4 * 3600
        let windowStart = optimalReturn.addingTimeInterval(-windowRadius)
        let windowEnd   = optimalReturn.addingTimeInterval(windowRadius)
        let atRiskCount = forgettingTimes.filter {
            $0 >= windowStart && $0 <= windowEnd
        }.count

        let riskScore = Double(atRiskCount) / Double(items.count)

        // Don't generate for trivially low risk.
        guard atRiskCount >= 2 || items.count <= 3 else { return nil }

        return ReturnIntent(
            documentID:      document.id,
            documentTitle:   document.title,
            cardCount:       max(1, atRiskCount),
            optimalReturnAt: optimalReturn,
            windowHours:     8,
            riskScore:       riskScore,
            generatedAt:     now
        )
    }
}

// MARK: - ReturnIntentStore

/// Thin persistence wrapper. One active intent at a time.
/// Backed by UserDefaults so it survives app kills and relaunch.
/// Consumed exclusively by StudyDecision.resolve() — not rendered directly.
final class ReturnIntentStore {

    static let shared = ReturnIntentStore()
    private init() {}

    private let key = "verba.returnIntent.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Read

    var current: ReturnIntent? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let intent = try? decoder.decode(ReturnIntent.self, from: data)
        else { return nil }
        if intent.isExpired {
            clear()
            return nil
        }
        return intent
    }

    // MARK: - Write

    /// Save a new intent, replacing any previous one.
    /// Keeps existing intent if it's active and has a higher risk score.
    func save(_ intent: ReturnIntent) {
        if let existing = current,
           existing.isWithinWindow,
           existing.riskScore >= intent.riskScore {
            return
        }
        guard let data = try? encoder.encode(intent) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Called when the user acts on the intent — prevents re-surfacing after study.
    func markConsumed() {
        clear()
    }
}
