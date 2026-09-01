import Foundation
import SwiftData

// MARK: - ChallengeManager
//
// Owns the VerbaFlowEngine and StudyQueueManager for a single runner run.
// Responsibilities:
//   • Start / end the SRS engine session when the run begins / ends.
//   • Decide when a gate obstacle should appear (distance-based interval scaled by mode).
//   • Select the gate card (worst-stuck card, fallback to random).
//   • Process the player's gate answer through the existing SRS pipeline.
//
// Threading: @MainActor throughout (matches VerbaFlowEngine's isolation).
//
// No SwiftUI dependency — this is pure game/engine coordination.

@MainActor
final class ChallengeManager {

    // MARK: - Owned sub-systems

    let engine       = VerbaFlowEngine()
    let queueManager = StudyQueueManager()

    // MARK: - Gate state

    /// Card waiting to be spawned as a gate obstacle (set by checkAndQueueGate).
    private(set) var pendingGateCard: StudyItem? = nil

    /// Card currently shown in the QuestionOverlayView (moved from pending on gate hit).
    private(set) var activeGateCard: StudyItem?  = nil

    // MARK: - Run stats

    private(set) var gatesFired:   Int = 0
    private(set) var gatesCorrect: Int = 0

    // MARK: - Internal state

    private var allItems:          [StudyItem] = []
    private var lastGateDistance:  Int         = 0

    // MARK: - Session lifecycle

    /// Called at the start of each run (including replays).
    func startSession(from items: [StudyItem]) {
        allItems          = items
        lastGateDistance  = 0
        gatesFired        = 0
        gatesCorrect      = 0
        pendingGateCard   = nil
        activeGateCard    = nil

        guard !items.isEmpty else { return }
        engine.buildSession(from: items, queueManager: queueManager)
    }

    /// Called when the run ends (game over or explicit exit).
    /// Returns gate statistics for inclusion in RunResult.
    @discardableResult
    func endSession() -> (answered: Int, correct: Int) {
        engine.endSession()
        pendingGateCard = nil
        activeGateCard  = nil
        return (gatesFired, gatesCorrect)
    }

    // MARK: - Gate lifecycle

    /// Called every frame (via RunSessionManager's onScoreUpdate callback).
    /// Returns true once when a gate should be queued for the next obstacle spawn.
    /// Fast-path (O(1)) until interval is met; card selection (O(n log n)) only on trigger.
    func checkAndQueueGate(distance: Int) -> Bool {
        // Gates require items; avoid if overlay or pending spawn already active.
        guard !allItems.isEmpty,
              activeGateCard == nil,
              pendingGateCard == nil else { return false }

        let snapshot = EngineSnapshot(energy: engine.energy, mode: engine.mode)
        let interval = GameBridge.gateDistanceInterval(for: snapshot)
        guard distance - lastGateDistance >= interval else { return false }

        // Select worst-stuck card; fall back to random from all items.
        let candidates = allItems
            .filter { $0.consecutiveMisses >= 1 }
            .sorted { $0.consecutiveMisses > $1.consecutiveMisses }
        guard let card = candidates.first ?? allItems.randomElement() else { return false }

        pendingGateCard = card
        return true
    }

    /// Called by RunSessionManager when the gate obstacle is physically hit.
    /// Moves the card from pending → active and returns it with shuffled multiple-choice options.
    /// The returned choices array always includes the correct answer; length is 2–4 depending on pool size.
    @discardableResult
    func activateGate(atDistance distance: Int) -> (card: StudyItem, choices: [String])? {
        guard let card = pendingGateCard else { return nil }
        activeGateCard   = card
        pendingGateCard  = nil
        lastGateDistance = distance
        gatesFired      += 1

        // Build distractor pool from other items' answers, deduplicating against correct answer.
        let correct    = card.answer
        let distractors = allItems
            .filter { $0.id != card.id && $0.answer != correct }
            .shuffled()
            .prefix(3)
            .map { $0.answer }
        let choices = ([correct] + distractors).shuffled()
        return (card, choices)
    }

    /// Called after the player taps an answer in QuestionOverlayView.
    /// Feeds the result through VerbaFlowEngine's full SRS pipeline.
    func processGateAnswer(correct: Bool, card: StudyItem, save: () -> Void) {
        if correct { gatesCorrect += 1 }
        activeGateCard = nil

        guard !allItems.isEmpty else { return }
        engine.processAnswer(
            correct:      correct,
            card:         card,
            queueManager: queueManager,
            save:         save
        )

        // Push updated card state to Firestore so gate answers sync across devices.
        // StudyScheduler.processAnswer() stamps lastModified = now, so the
        // CloudSyncEngine's LWW cursor will pick this up in the next incremental pull.
        CloudSyncEngine.shared.enqueueStudyItemSync(id: card.id)
    }

    // MARK: - Engine snapshot (for GameBridge translation)

    var engineSnapshot: EngineSnapshot {
        EngineSnapshot(energy: engine.energy, mode: engine.mode)
    }
}
