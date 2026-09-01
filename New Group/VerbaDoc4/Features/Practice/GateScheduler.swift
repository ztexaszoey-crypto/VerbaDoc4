import Foundation
import SwiftData

/// Determines WHEN a knowledge gate fires and WHICH card to use.
///
/// A gate is a deterministic flashcard checkpoint — not a game event.
/// Triggered by: cards-answered interval OR mastery weakness threshold.
/// The gate card is always the most persistently wrong item in the queue.
///
/// Frustration control: if the student answers 3+ consecutive cards wrong,
/// the gate interval expands by 4 to prevent compounding frustration.
struct GateScheduler {

    /// Cards answered since the last gate fired.
    private(set) var cardsSinceLastGate: Int = 0

    /// Consecutive wrong answers — drives frustration control.
    private(set) var consecutiveWrongAnswers: Int = 0

    // MARK: - Interval

    /// Base gate interval per mode. Lower energy → denser gates.
    /// High mastery / flow state → fewer interruptions.
    func gateInterval(for mode: VerbaFlowEngine.FlowMode) -> Int {
        switch mode {
        case .flow:     return 12   // locked in → less frequent checkpoints
        case .normal:   return 8
        case .review:   return 5
        case .recovery: return 3    // recovery → near-constant reinforcement
        }
    }

    // MARK: - Record

    /// Called on every answer (gate or normal). Maintains scheduling state.
    mutating func recordAnswer(correct: Bool) {
        cardsSinceLastGate += 1
        consecutiveWrongAnswers = correct ? 0 : consecutiveWrongAnswers + 1
    }

    /// Reset interval counter after a gate fires.
    mutating func recordGateFired() {
        cardsSinceLastGate = 0
    }

    // MARK: - Decision

    /// True when a gate card should be injected before the next card.
    /// Returns false if no weak cards are available.
    func shouldTriggerGate(mode: VerbaFlowEngine.FlowMode, weakCards: [StudyItem]) -> Bool {
        guard !weakCards.isEmpty else { return false }
        let base = gateInterval(for: mode)
        // Frustration control: expand interval when student is struggling
        let effective = consecutiveWrongAnswers >= 3 ? base + 4 : base
        return cardsSinceLastGate >= effective
    }

    /// Selects the gate card: the item with the most consecutive misses.
    /// Returns nil if weakCards is empty.
    func selectGateCard(from weakCards: [StudyItem]) -> StudyItem? {
        weakCards
            .sorted { $0.consecutiveMisses > $1.consecutiveMisses }
            .first
    }
}
