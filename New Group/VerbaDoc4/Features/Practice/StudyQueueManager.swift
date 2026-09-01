import Foundation
import SwiftData

// MARK: - StudyQueueManager
//
// THE single authority for all study session queue state.
//
// Ownership contract (non-negotiable):
//   ONLY this class may insert, remove, reorder, or advance cards in the session queue.
//   ALL other systems (FlashcardStudyView, VerbaFlowEngine, GateScheduler, recovery logic)
//   are PURE: they request queue mutations via this class's methods, never touch the
//   array directly.
//
// Invariants enforced after every mutation:
//   • No card appears at two consecutive upcoming positions (no back-to-back duplicates).
//   • currentIndex only moves forward via commitAdvance().
//   • sessionComplete is set exactly once when currentIndex reaches queue.count.
//
// Two sessions (FlashcardStudyView + VerbaFlowView) each own their own manager instance.
// They never share state — the contract is per-session, not app-global.

@MainActor
final class StudyQueueManager: ObservableObject {

    // MARK: - Published State (read-only outside this class)

    @Published private(set) var queue:           [StudyItem] = []
    @Published private(set) var currentIndex:    Int         = 0
    @Published private(set) var isAdvancing:     Bool        = false
    @Published private(set) var sessionComplete: Bool        = false

    // MARK: - Derived (safe to read from any view)

    var currentCard: StudyItem? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var progress: Double {
        queue.isEmpty ? 0 : Double(currentIndex) / Double(queue.count)
    }

    var remainingCount: Int {
        max(0, queue.count - currentIndex)
    }

    // MARK: - Build (call once at session start)

    /// Builds the queue from a scoped item set, SRS-ordered (overdue weakest-first, then remaining weakest-first).
    func build(from items: [StudyItem], scope: DrillScope = .all) {
        let now = Date()
        let scoped: [StudyItem] = {
            switch scope {
            case .all:           return items
            case .weak:          return items.filter { $0.mastery < 50 }
            case .due:           return items.filter { $0.nextReviewAt <= now }
            case .topic(let t):  return items.filter { $0.topic == t }
            }
        }()
        let due    = scoped.filter { $0.nextReviewAt <= now }.sorted { $0.mastery < $1.mastery }
        let notDue = scoped.filter { $0.nextReviewAt > now  }.sorted { $0.mastery < $1.mastery }
        queue = due + notDue
        resetCursor()
    }

    /// Builds from all items, capped at `cap` cards, SRS-ordered.
    /// Blends due maintenance/archived cards (daily warmup) into the queue so
    /// long-term retention cards surface even when the active deck is large.
    ///
    /// Warmup slot budget: up to 5 cards, inserted after the first batch of due
    /// active cards so they feel integrated, not tacked-on.
    func buildWithWarmup(from items: [StudyItem], cap: Int = 25) {
        let now = Date()

        // ── Active cards (primary session material) ───────────────────────────
        let active    = items.filter { $0.cardLayer == "active" }
        let activeDue = active.filter { $0.nextReviewAt <= now }.sorted { $0.mastery < $1.mastery }
        let activeNot = active.filter { $0.nextReviewAt > now  }.sorted { $0.mastery < $1.mastery }

        // ── Warmup candidates (maintenance / archived cards that are due) ─────
        let warmup = items
            .filter { ($0.cardLayer == "maintenance" || $0.cardLayer == "archived")
                       && $0.nextReviewAt <= now }
            .sorted { $0.mastery < $1.mastery }
            .prefix(5)

        let warmupSlots  = warmup.count
        let activeSlots  = max(0, cap - warmupSlots)
        let activeCards  = Array((activeDue + activeNot).prefix(activeSlots))

        // ── Interleave warmup after the first run of due active cards ─────────
        // Keeps exam-critical active cards at the front while warmup cards appear
        // naturally mid-session rather than as a trailing bonus.
        var result = activeCards
        if !warmup.isEmpty {
            // Insert warmup cards right after the due-active segment
            let insertPoint = min(activeDue.count, activeCards.count)
            result.insert(contentsOf: warmup, at: insertPoint)
        }

        queue = result
        resetCursor()
    }

    // MARK: - Queue Mutations (all entry points; all enforce invariants)

    /// Re-inserts a missed card 3 positions ahead.
    /// No-op if the card already appears within the next 3 positions.
    func requeueMissed(_ card: StudyItem) {
        guard !isCardUpcoming(card, within: 3) else { return }
        let insertAt = min(currentIndex + 3, queue.count)
        queue.insert(card, at: insertAt)
        assertInvariants()
    }

    /// Injects a gate card at position currentIndex + 1.
    /// No-op if the card already appears within the next 3 positions.
    func injectGate(_ card: StudyItem) {
        guard !isCardUpcoming(card, within: 3) else { return }
        queue.insert(card, at: min(currentIndex + 1, queue.count))
        assertInvariants()
    }

    /// Injects a failed gate card at position currentIndex + 2 (one buffer card).
    /// Using +2 (not +1) prevents the jarring "same card immediately again" experience
    /// while still keeping the reinforcement close.
    /// No-op if the card already appears within the next 3 positions.
    func injectFailedGate(_ card: StudyItem) {
        guard !isCardUpcoming(card, within: 3) else { return }
        queue.insert(card, at: min(currentIndex + 2, queue.count))
        assertInvariants()
    }

    /// Injects recovery cards immediately after current position, deduped against the next `lookAhead` positions.
    /// Cards are inserted in order; at most `limit` cards are injected.
    func injectRecovery(candidates: [StudyItem], limit: Int = 3, lookAhead: Int = 5) {
        let toInject = candidates
            .filter { !isCardUpcoming($0, within: lookAhead) }
            .prefix(limit)
        for (offset, card) in toInject.enumerated() {
            queue.insert(card, at: min(currentIndex + 1 + offset, queue.count))
        }
        if !toInject.isEmpty { assertInvariants() }
    }

    /// Injects the highest-mastery unseen card (≥ 55 mastery) as an easy win.
    /// Respects DrillScope — topic sessions only inject from the same topic.
    /// No-op if no eligible card exists.
    func injectEasyWin(from pool: [StudyItem], scope: DrillScope) {
        let seenIDs: Set<String> = Set(queue.prefix(currentIndex + 1).map { $0.id })
        let candidates: [StudyItem] = {
            if case .topic(let t) = scope { return pool.filter { $0.topic == t } }
            return pool
        }()
        guard let easy = candidates.filter({
            !seenIDs.contains($0.id) && !isCardUpcoming($0, within: 5) && $0.mastery >= 55
        }).max(by: { $0.mastery < $1.mastery }) else { return }
        queue.insert(easy, at: min(currentIndex + 1, queue.count))
        assertInvariants()
    }

    // MARK: - Cursor Control

    /// Marks the beginning of a card transition. Disables all input while advancing.
    func beginAdvance() {
        isAdvancing = true
    }

    /// Moves to the next card and clears the advancing lock.
    /// Sets sessionComplete when the last card is passed.
    func commitAdvance() {
        currentIndex += 1
        isAdvancing   = false
        if currentIndex >= queue.count { sessionComplete = true }
    }

    // MARK: - Private Helpers

    private func resetCursor() {
        currentIndex    = 0
        isAdvancing     = false
        sessionComplete = false
        assertInvariants()
    }

    /// Returns true if `card` already appears in any of the next `positions` slots after currentIndex.
    private func isCardUpcoming(_ card: StudyItem, within positions: Int) -> Bool {
        let start = min(currentIndex + 1, queue.count)
        let end   = min(start + positions, queue.count)
        guard start < end else { return false }
        return queue[start..<end].contains { $0.id == card.id }
    }

    // MARK: - Invariant Validation (DEBUG only)
    //
    // Runs after every mutation. Prints a warning if consecutive duplicates
    // are detected in the upcoming portion of the queue.
    // This is a detection tool — the deduplication logic in mutation methods
    // is the prevention tool.

    private func assertInvariants() {
        #if DEBUG
        guard queue.count > currentIndex + 1 else { return }
        let upcoming = queue[currentIndex...]
        let ids = upcoming.map { $0.id }
        for i in 0..<(ids.count - 1) where ids[i] == ids[i + 1] {
            let label = queue[currentIndex + i].question.prefix(50)
            print("[StudyQueueManager] ⚠️ CONSECUTIVE DUPLICATE at upcoming[\(i)]: '\(label)'")
        }
        #endif
    }
}
