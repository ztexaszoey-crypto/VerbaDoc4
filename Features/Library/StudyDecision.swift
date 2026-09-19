import SwiftUI
import Foundation

// MARK: - StudyDecision
//
// THE single source of truth for "what should the user do right now?"
//
// Architecture rule: ONE resolver → ONE enum → UI is dumb rendering only.
//
// All signals (SRS due dates, ReturnIntent forgetting curve, mastery) feed
// into resolve(). Nothing renders independently. There is no priority stack
// in the UI — the stack lives here, explicitly, with a single exit point.
//
// Priority order (first match wins):
//   1. memoryRisk   — ReturnIntent window open + SRS confirms work to do
//   2. due          — SRS scheduler: nextReviewAt <= now
//   3. missedWindow — ReturnIntent missed but not expired (soft recovery)
//   4. weak         — mastery < 50, nothing due yet
//   5. fresh        — deck exists but has never been studied
//   6. allCaughtUp  — nothing urgent, show time-to-next
//   7. noDecks      — empty library

enum StudyDecision {

    case memoryRisk(document: Document, count: Int, intent: ReturnIntent)
    case due(document: Document, count: Int)
    case missedWindow(document: Document, count: Int, intent: ReturnIntent)
    case weak(document: Document, count: Int)
    case fresh(document: Document)
    case allCaughtUp(nextReviewIn: TimeInterval?)
    case noDecks

    // MARK: - Single Resolver

    static func resolve(from documents: [Document]) -> StudyDecision {
        let active = documents.filter { !$0.isArchived }
        guard !active.isEmpty else { return .noDecks }

        let now    = Date()
        let intent = ReturnIntentStore.shared.current  // nil if expired or absent

        // Diagnostic: capture signal disagreements before deciding.
        ConflictLog.record(active: active, intent: intent, now: now)

        // ── 1. Memory risk window open ────────────────────────────────────────
        // ReturnIntent says "now is the forgetting threshold" AND
        // SRS agrees there is real work (due cards) or risk is high (≥0.5).
        // Both signals must point in the same direction. If they disagree,
        // fall through to SRS (the ground truth).
        if let intent, intent.isWithinWindow,
           let doc = active.first(where: { $0.id == intent.documentID }) {
            let dueCount  = doc.studyItems.filter { $0.nextReviewAt <= now }.count
            let riskCount = max(intent.cardCount, dueCount)
            if dueCount > 0 || intent.riskScore >= 0.5 {
                return .memoryRisk(document: doc, count: riskCount, intent: intent)
            }
            // ReturnIntent fired but SRS has nothing due and risk is low.
            // Conflict already logged. Fall through to SRS.
        }

        // ── 2. SRS due cards ──────────────────────────────────────────────────
        var bestDueDoc: Document?
        var bestDueCount = 0
        for doc in active {
            let n = doc.studyItems.filter { $0.nextReviewAt <= now }.count
            if n > bestDueCount { bestDueCount = n; bestDueDoc = doc }
        }
        if let doc = bestDueDoc, bestDueCount > 0 {
            return .due(document: doc, count: bestDueCount)
        }

        // ── 3. Missed window — soft recovery ──────────────────────────────────
        // ReturnIntent window has passed but the intent hasn't expired.
        // No guilt — just "you can still catch up."
        if let intent, intent.isMissed,
           let doc = active.first(where: { $0.id == intent.documentID }) {
            return .missedWindow(document: doc, count: intent.cardCount, intent: intent)
        }

        // ── 4. Weak mastery ───────────────────────────────────────────────────
        var bestWeakDoc: Document?
        var bestWeakCount = 0
        for doc in active {
            let n = doc.studyItems.filter { $0.mastery < 50 }.count
            if n > bestWeakCount { bestWeakCount = n; bestWeakDoc = doc }
        }
        if let doc = bestWeakDoc, bestWeakCount > 0 {
            return .weak(document: doc, count: bestWeakCount)
        }

        // ── 5. Fresh deck ─────────────────────────────────────────────────────
        for doc in active.reversed() {
            if doc.studyItems.contains(where: { $0.reviewCount == 0 }) {
                return .fresh(document: doc)
            }
        }

        // ── 6. All caught up ──────────────────────────────────────────────────
        let allItems = active.flatMap { $0.studyItems }
        let nearest  = allItems.filter { $0.nextReviewAt > now }.map(\.nextReviewAt).min()
        return .allCaughtUp(nextReviewIn: nearest.map { $0.timeIntervalSince(now) })
    }

    // MARK: - Display helpers
    // All copy and visual metadata lives here — UI reads these, decides nothing.

    var document: Document? {
        switch self {
        case .memoryRisk(let doc, _, _):    return doc
        case .due(let doc, _):              return doc
        case .missedWindow(let doc, _, _):  return doc
        case .weak(let doc, _):             return doc
        case .fresh(let doc):               return doc
        default:                            return nil
        }
    }

    var isActionable: Bool {
        switch self {
        case .allCaughtUp, .noDecks: return false
        default:                     return true
        }
    }

    /// Which cards to load when the CTA fires.
    var drillScope: DrillScope {
        switch self {
        case .memoryRisk, .due, .missedWindow: return .due
        case .weak:                            return .weak
        default:                               return .all
        }
    }

    /// Accent colour — orange for urgency, green for normal, muted for soft.
    var accentColor: Color {
        switch self {
        case .memoryRisk(_, _, let intent):
            return intent.urgency == .high ? VerbaTheme.orange : VerbaTheme.green
        case .due:          return VerbaTheme.orange
        case .missedWindow: return VerbaTheme.muted
        case .weak:         return VerbaTheme.danger
        case .fresh:        return VerbaTheme.green
        default:            return VerbaTheme.green
        }
    }

    /// Short chip label above the deck title.
    var chipLabel: String {
        switch self {
        case .memoryRisk(_, _, let intent):
            switch intent.urgency {
            case .high:   return "memory window open"
            case .medium: return "good time to review"
            case .low:    return "coming up"
            }
        case .due:          return "due for review"
        case .missedWindow: return "window passed · catch up"
        case .weak:         return "weak spots"
        case .fresh:        return "new deck"
        default:            return ""
        }
    }

    var chipIcon: String {
        switch self {
        case .memoryRisk(_, _, let intent):
            return intent.urgency == .high ? "exclamationmark.triangle.fill" : "clock.fill"
        case .due:          return "clock.fill"
        case .missedWindow: return "arrow.uturn.left"
        case .weak:         return "bolt.fill"
        case .fresh:        return "sparkles"
        default:            return ""
        }
    }

    var headline: String {
        switch self {
        case .memoryRisk(_, _, let intent):
            return intent.headline
        case .due(let doc, let n):
            return "\(n) card\(n == 1 ? "" : "s") due · \(doc.title)"
        case .missedWindow(let doc, let n, _):
            return "\(n) card\(n == 1 ? "" : "s") slipped · \(doc.title)"
        case .weak(let doc, let n):
            return "\(n) weak spot\(n == 1 ? "" : "s") · \(doc.title)"
        case .fresh(let doc):
            return "start studying · \(doc.title)"
        case .allCaughtUp(let interval):
            if let t = interval { return "next review \(Self.intervalLabel(t))" }
            return "all caught up"
        case .noDecks:
            return "add your first deck"
        }
    }

    var ctaLabel: String {
        switch self {
        case .memoryRisk(_, _, let intent):
            return intent.ctaLabel
        case .due(_, let n):
            return "study now · \(Self.minuteLabel(n))"
        case .missedWindow(_, let n, _):
            return "catch up · \(Self.minuteLabel(n))"
        case .weak(_, let n):
            return "drill weak spots · \(Self.minuteLabel(n))"
        case .fresh(let doc):
            return "start · \(Self.minuteLabel(doc.studyItems.count))"
        default:
            return ""
        }
    }

    var detailLine: String {
        switch self {
        case .memoryRisk(let doc, let n, _), .due(let doc, let n), .weak(let doc, let n),
             .missedWindow(let doc, let n, _):
            return "\(n) card\(n == 1 ? "" : "s") · ~\(max(1, n * 20 / 60)) min · \(doc.title)"
        case .fresh(let doc):
            let n = doc.studyItems.count
            return "\(n) card\(n == 1 ? "" : "s") · first session"
        default:
            return ""
        }
    }

    // MARK: - Formatting

    private static func minuteLabel(_ cardCount: Int) -> String {
        let mins = max(1, Int((Double(cardCount * 20) / 60).rounded()))
        return "~\(mins) min"
    }

    static func intervalLabel(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        if hours < 1  { return "in < 1 hour" }
        if hours < 24 { return "in \(hours)h" }
        let days = hours / 24
        return "in \(days) day\(days == 1 ? "" : "s")"
    }
}

// MARK: - ConflictLog
//
// Diagnostic only. Captures signal disagreements at resolve-time.
// DEBUG builds: prints to console with structured tags.
// RELEASE builds: zero-cost (entirely compiled out).
//
// Conflict types:
//   A — ReturnIntent window open, SRS reports 0 due cards → overconfident prediction
//   B — ReturnIntent points to deleted document → stale intent, auto-cleared
//   C — ReturnIntent fires for doc X, SRS urgency is on doc Y → split-attention signal

enum ConflictLog {

    static func record(active: [Document], intent: ReturnIntent?, now: Date) {
        #if DEBUG
        guard let intent else { return }

        let intentDoc = active.first(where: { $0.id == intent.documentID })
        let dueForIntentDoc = intentDoc?.studyItems.filter { $0.nextReviewAt <= now }.count ?? 0

        // A: Intent window open but SRS shows 0 due cards
        if intent.isWithinWindow && dueForIntentDoc == 0 {
            print("""
            ⚠️  [StudyDecision·A] Overconfident intent: \
            ReturnIntent window open for '\(intent.documentTitle)' \
            but SRS has 0 due cards. riskScore=\(String(format: "%.2f", intent.riskScore))
            """)
        }

        // B: Intent references a document that no longer exists
        if intentDoc == nil {
            print("""
            ⚠️  [StudyDecision·B] Stale intent: \
            '\(intent.documentTitle)' not found in active library. Clearing.
            """)
            ReturnIntentStore.shared.clear()
        }

        // C: Top SRS-due document differs from intent's document
        if let intentDoc {
            var topDueDoc: Document?
            var topDue = 0
            for doc in active {
                let n = doc.studyItems.filter { $0.nextReviewAt <= now }.count
                if n > topDue { topDue = n; topDueDoc = doc }
            }
            if let topDueDoc, topDueDoc.id != intentDoc.id, topDue > 0 {
                print("""
                ⚠️  [StudyDecision·C] Signal split: \
                ReturnIntent → '\(intent.documentTitle)', \
                SRS top-due → '\(topDueDoc.title)' (\(topDue) cards). \
                SRS wins unless riskScore ≥ 0.5.
                """)
            }
        }
        #endif
    }
}
