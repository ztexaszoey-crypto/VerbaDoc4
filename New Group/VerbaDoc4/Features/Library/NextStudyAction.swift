import Foundation

// MARK: - NextStudyAction  [SUPERSEDED]
//
// Replaced by StudyDecision, which unifies ReturnIntent + SRS signals into
// a single resolver. This file is kept for reference only.
// DO NOT use NextStudyAction in new UI code — use StudyDecision.resolve() instead.
//
// Original priority order (now encoded inside StudyDecision):
//   1. Due review cards   — cards where nextReviewAt <= now
//   2. Weak cards         — mastery < 50, not yet due
//   3. Fresh deck         — never studied (reviewCount == 0)
//   4. All caught up      — nothing urgent
//   5. No decks

enum NextStudyAction {

    /// Due reviews exist — this is the highest-priority signal.
    case due(document: Document, count: Int)

    /// No due cards, but mastery is weak on these — drill them before they slip.
    case weak(document: Document, count: Int)

    /// A deck that's never been studied. Prompt the first session.
    case fresh(document: Document)

    /// Everything is mastered and not due yet. Show next review time.
    case allCaughtUp(nextReviewIn: TimeInterval?)

    /// No decks exist at all.
    case noDecks

    // MARK: - Computation

    static func compute(from documents: [Document]) -> NextStudyAction {
        let active = documents.filter { !$0.isArchived }
        guard !active.isEmpty else { return .noDecks }

        let now = Date()

        // ── 1. Due cards ──────────────────────────────────────────────────────
        // Pick the document with the most overdue cards.
        var bestDueDoc: Document? = nil
        var bestDueCount = 0
        for doc in active {
            let due = doc.studyItems.filter { $0.nextReviewAt <= now }.count
            if due > bestDueCount {
                bestDueCount = due
                bestDueDoc = doc
            }
        }
        if let doc = bestDueDoc, bestDueCount > 0 {
            return .due(document: doc, count: bestDueCount)
        }

        // ── 2. Weak cards ─────────────────────────────────────────────────────
        // No due cards, but something is below 50% mastery.
        var bestWeakDoc: Document? = nil
        var bestWeakCount = 0
        for doc in active {
            let weak = doc.studyItems.filter { $0.mastery < 50 }.count
            if weak > bestWeakCount {
                bestWeakCount = weak
                bestWeakDoc = doc
            }
        }
        if let doc = bestWeakDoc, bestWeakCount > 0 {
            return .weak(document: doc, count: bestWeakCount)
        }

        // ── 3. Fresh deck ─────────────────────────────────────────────────────
        // Has cards but none have been reviewed yet (all reviewCount == 0).
        for doc in active.reversed() {  // reversed = oldest first (least recently created)
            let unreviewed = doc.studyItems.filter { $0.reviewCount == 0 }.count
            if unreviewed > 0 {
                return .fresh(document: doc)
            }
        }

        // ── 4. All caught up ──────────────────────────────────────────────────
        // Find the nearest upcoming review across all decks.
        let allItems = active.flatMap { $0.studyItems }
        let nearest = allItems
            .filter { $0.nextReviewAt > now }
            .map(\.nextReviewAt)
            .min()
        let interval = nearest.map { $0.timeIntervalSince(now) }
        return .allCaughtUp(nextReviewIn: interval)
    }

    // MARK: - Display helpers

    var document: Document? {
        switch self {
        case .due(let doc, _):   return doc
        case .weak(let doc, _):  return doc
        case .fresh(let doc):    return doc
        default:                 return nil
        }
    }

    var headline: String {
        switch self {
        case .due(let doc, let n):
            return "\(n) card\(n == 1 ? "" : "s") due · \(doc.title)"
        case .weak(let doc, let n):
            return "\(n) weak spot\(n == 1 ? "" : "s") · \(doc.title)"
        case .fresh(let doc):
            return "start studying · \(doc.title)"
        case .allCaughtUp(let interval):
            if let t = interval {
                return "next review \(NextStudyAction.intervalLabel(t))"
            }
            return "all caught up"
        case .noDecks:
            return "add your first deck"
        }
    }

    var ctaLabel: String {
        switch self {
        case .due(_, let n):     return "study now · \(NextStudyAction.minuteLabel(n))"
        case .weak(_, let n):    return "drill weak spots · \(NextStudyAction.minuteLabel(n))"
        case .fresh(let doc):
            let n = doc.studyItems.count
            return "start · \(NextStudyAction.minuteLabel(n))"
        case .allCaughtUp:       return ""
        case .noDecks:           return ""
        }
    }

    var isActionable: Bool {
        switch self {
        case .due, .weak, .fresh: return true
        default:                  return false
        }
    }

    var drillScope: DrillScope {
        switch self {
        case .due:   return .due
        case .weak:  return .weak
        default:     return .all
        }
    }

    // MARK: - Private formatting

    private static func minuteLabel(_ cardCount: Int) -> String {
        // ~20 seconds per card (read + flip + decide)
        let seconds = cardCount * 20
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        return "~\(minutes) min"
    }

    static func intervalLabel(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        if hours < 1  { return "in < 1 hour" }
        if hours < 24 { return "in \(hours)h" }
        let days = hours / 24
        return "in \(days) day\(days == 1 ? "" : "s")"
    }
}
