import Foundation
import SwiftData

// MARK: - VerbaFlowEngine
//
// Pure energy/mode/streak state machine for the VerbaFlow study session.
//
// Ownership boundary (strictly enforced):
//   VerbaFlowEngine owns ONLY: energy, mode, streaks, session stats, gate scheduling.
//   VerbaFlowEngine does NOT own: queue, currentIndex, sessionComplete, isAdvancing.
//   All queue mutations go through StudyQueueManager — engine calls its methods,
//   never touches the queue array directly.
//
// Callers pass their StudyQueueManager instance into buildSession() and processAnswer().
// The engine reads from queueManager (currentCard, remainingCount, etc.) but never writes.

@MainActor
final class VerbaFlowEngine: ObservableObject {

    // MARK: - Session State

    enum FlowMode: String {
        case flow     = "FLOW"
        case normal   = "NORMAL"
        case review   = "REVIEW"
        case recovery = "RECOVERY"

        var lowerBound: Double {
            switch self {
            case .flow:     return 80
            case .normal:   return 40
            case .review:   return 10
            case .recovery: return 0
            }
        }
    }

    // MARK: - Published State (energy, mode, stats — not queue state)

    @Published private(set) var energy:            Double    = 50
    @Published private(set) var mode:              FlowMode  = .normal
    @Published private(set) var sessionCards:      Int       = 0
    @Published private(set) var sessionCorrect:    Int       = 0
    @Published private(set) var streakCount:       Int       = 0
    @Published private(set) var peakStreak:        Int       = 0
    @Published private(set) var currentCardIsGate: Bool      = false
    @Published private(set) var sessionStartEnergy: Double   = 50

    // MARK: - Derived

    var accuracy: Double {
        sessionCards > 0 ? Double(sessionCorrect) / Double(sessionCards) : 0
    }

    /// Scales 0.5–1.5 with energy. Used by FlowUIController for transition pacing.
    var flowSpeedMultiplier: Double {
        max(0.5, energy / 100.0 * 1.5)
    }

    var peakModeReached: FlowMode { _peakMode }

    // MARK: - Sub-systems

    private(set) var masteryTracker: MasteryTracker? = nil
    private var gateScheduler = GateScheduler()

    // MARK: - Internal State

    private var _peakMode: FlowMode = .normal
    private var nextCardIsGate: Bool = false
    private var idleDecayTask: Task<Void, Never>? = nil
    // Fix F-3: stored so endSession()/restart() can cancel it before sessionActive
    // turns false. Without cancellation, the 120ms-delayed commitAdvance() fires
    // on a dead session and awards phantom XP, haptics, and streak credit.
    private var advanceTask: Task<Void, Never>? = nil
    private var lastAnswerTimestamp: Date? = nil
    private let minimumAnswerInterval: TimeInterval = 1.5

    // MARK: - Session Control

    /// Build a session using the provided queue manager.
    /// The manager owns queue state; this method resets engine-owned state only.
    func buildSession(from items: [StudyItem], queueManager: StudyQueueManager) {
        queueManager.buildWithWarmup(from: items, cap: 25)

        // ── Session-start energy: reflects actual vault health ─────────────────
        // A student returning with a heavily decayed vault starts in review mode
        // so the engine immediately applies the right pacing and gate density.
        let startEnergy    = computeStartingEnergy(from: items)

        sessionCards       = 0
        sessionCorrect     = 0
        streakCount        = 0
        peakStreak         = 0
        currentCardIsGate  = false
        nextCardIsGate     = false
        energy             = startEnergy
        sessionStartEnergy = startEnergy
        _peakMode          = modeForEnergy(startEnergy)
        mode               = _peakMode

        gateScheduler    = GateScheduler()
        masteryTracker   = MasteryTracker(items: items)
        lastAnswerTimestamp = nil

        // ── Chronic-miss early injection ──────────────────────────────────────
        // Cards with 4+ consecutive misses are front-loaded into positions 2–4
        // so the session confronts the worst stuck cards immediately rather than
        // waiting for gate scheduling to surface them mid-session.
        let chronicStuck = queueManager.queue
            .filter { $0.consecutiveMisses >= 4 }
            .sorted { $0.consecutiveMisses > $1.consecutiveMisses }
            .prefix(2)
        if !chronicStuck.isEmpty {
            let firstFewIDs = Set(queueManager.queue.prefix(4).map { $0.id })
            let toInject = Array(chronicStuck).filter { !firstFewIDs.contains($0.id) }
            if !toInject.isEmpty {
                queueManager.injectRecovery(candidates: Array(toInject), limit: 2, lookAhead: 5)
            }
        }

        // Block background Firestore pull-merge for the duration of this session
        // to prevent mid-session SwiftData mutations from racing with queue reads.
        CloudSyncEngine.shared.isSessionActive = true

        startIdleDecay()
    }

    func restart(from items: [StudyItem], queueManager: StudyQueueManager) {
        advanceTask?.cancel()
        advanceTask = nil
        stopIdleDecay()
        buildSession(from: items, queueManager: queueManager)
    }

    /// Call when the session view disappears mid-session (user navigates away)
    /// OR when the user explicitly taps "end" during a session.
    /// Cancels the in-flight advance task so no phantom awards fire.
    func endSession() {
        advanceTask?.cancel()
        advanceTask = nil
        stopIdleDecay()
        // Unblock Firestore sync now that the session is done.
        CloudSyncEngine.shared.isSessionActive = false
    }

    // MARK: - Answer Processing

    /// Process a student answer.
    /// `queueManager` is passed in — engine calls its methods but never mutates its state directly.
    /// `save` keeps the engine context-free (no modelContext dependency).
    func processAnswer(
        correct: Bool,
        card: StudyItem,
        queueManager: StudyQueueManager,
        save: () -> Void
    ) {
        guard !queueManager.isAdvancing else { return }
        queueManager.beginAdvance()

        // ── 1. Anti-exploit: rapid correct tap = half energy gain ──────────
        let now = Date()
        var energyDelta: Double = correct ? 8.0 : -12.0
        if correct,
           let last = lastAnswerTimestamp,
           now.timeIntervalSince(last) < minimumAnswerInterval {
            energyDelta = 4.0
        }
        lastAnswerTimestamp = now

        // ── 2. Gate card handling ──────────────────────────────────────────
        let wasGate = currentCardIsGate
        if wasGate {
            if correct {
                energyDelta += 5.0
                bumpStreak()
            } else {
                masteryTracker?.recordGateWrong(item: card)
                // Failed gate: reinforce at +2 (one buffer card) so the student
                // isn't immediately hit with the same card again. Close enough
                // to provide reinforcement, far enough to not feel punitive.
                queueManager.injectFailedGate(card)
            }
            currentCardIsGate = false
        } else {
            if correct { bumpStreak() } else { streakCount = 0 }
        }

        // ── 3. Energy + mode ───────────────────────────────────────────────
        energy = max(0, min(100, energy + energyDelta))
        updateMode(queueManager: queueManager)

        // ── 4. Mastery + SRS scheduling ────────────────────────────────────
        StudyScheduler.processAnswer(card: card, correct: correct, now: now)
        save()

        // ── 5. Session stats ───────────────────────────────────────────────
        sessionCards += 1
        if correct { sessionCorrect += 1 }

        // ── 6. Wrong card re-queue (normal cards only — gate wrong handled above) ──
        if !correct && !wasGate {
            queueManager.requeueMissed(card)
        }

        // ── 7. Gate scheduler ──────────────────────────────────────────────
        gateScheduler.recordAnswer(correct: correct)

        let nextPos = queueManager.currentIndex + 1
        let weakArray: [StudyItem] = nextPos < queueManager.queue.count
            ? queueManager.queue[nextPos...].filter {
                $0.consecutiveMisses >= 2 && $0.id != card.id
              }
            : []

        if gateScheduler.shouldTriggerGate(mode: mode, weakCards: weakArray),
           let gateCard = gateScheduler.selectGateCard(from: weakArray) {
            let alreadyNext = queueManager.queue.indices.contains(nextPos)
                && queueManager.queue[nextPos].id == gateCard.id
            if !alreadyNext {
                queueManager.injectGate(gateCard)
            }
            nextCardIsGate = true
            gateScheduler.recordGateFired()
        }

        // ── 8. Reset idle decay ────────────────────────────────────────────
        startIdleDecay()

        // ── 9. Advance cursor (async, lets animations settle) ──────────────
        advance(queueManager: queueManager)
    }

    // MARK: - Private: Advance

    private func advance(queueManager: StudyQueueManager) {
        // Fix F-3: cancel any prior in-flight advance before creating a new one.
        // Rapid double-taps on accessibility actions could otherwise enqueue two
        // commitAdvance() calls, skipping a card and corrupting session stats.
        advanceTask?.cancel()
        advanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }

            queueManager.commitAdvance()

            if self.nextCardIsGate {
                self.currentCardIsGate = true
                self.nextCardIsGate    = false
            } else {
                self.currentCardIsGate = false
            }

            if queueManager.sessionComplete {
                self.stopIdleDecay()
            }
            // Task is done — nil the reference so endSession() doesn't
            // try to cancel a completed task on the next session teardown.
            self.advanceTask = nil
        }
    }

    // MARK: - Private: Mode

    private func updateMode(queueManager: StudyQueueManager) {
        let newMode: FlowMode
        switch energy {
        case 80...:    newMode = .flow
        case 40..<80:  newMode = .normal
        case 10..<40:  newMode = .review
        default:       newMode = .recovery
        }

        if newMode != mode {
            let wasRecovery = mode == .recovery
            mode = newMode
            if newMode == .recovery && !wasRecovery {
                activateRecoveryReinforcement(queueManager: queueManager)
            }
        }
        if newMode.lowerBound > _peakMode.lowerBound { _peakMode = newMode }
    }

    /// Delegates to StudyQueueManager.injectRecovery — engine provides candidates, manager handles insertion + dedup.
    private func activateRecoveryReinforcement(queueManager: StudyQueueManager) {
        let stuck = queueManager.queue
            .filter { $0.consecutiveMisses >= 2 }
            .sorted { $0.consecutiveMisses > $1.consecutiveMisses }
        queueManager.injectRecovery(candidates: Array(stuck), limit: 3, lookAhead: 5)
    }

    // MARK: - Private: Streak

    private func bumpStreak() {
        streakCount += 1
        if streakCount > peakStreak { peakStreak = streakCount }
    }

    // MARK: - Private: Idle Decay

    private func startIdleDecay() {
        idleDecayTask?.cancel()
        idleDecayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { break }
                self.energy = max(0, self.energy - 1)
                // updateMode requires queueManager but we don't have it here —
                // idle decay only affects energy, mode update deferred to next answer.
                // This is safe: mode is only used for gate interval tuning, not correctness.
                let newMode: FlowMode
                switch self.energy {
                case 80...:    newMode = .flow
                case 40..<80:  newMode = .normal
                case 10..<40:  newMode = .review
                default:       newMode = .recovery
                }
                if newMode != self.mode { self.mode = newMode }
            }
        }
    }

    private func stopIdleDecay() {
        idleDecayTask?.cancel()
        idleDecayTask = nil
    }

    // MARK: - Private: Session-Start Energy

    /// Computes the starting energy level from the current vault health.
    /// This determines which FlowMode the session opens in:
    ///   ≥65  → normal (approaching flow)
    ///   50   → normal (default)
    ///   35   → low normal (more review-like pacing)
    ///   25   → review (heavy decay / returning student)
    private func computeStartingEnergy(from items: [StudyItem]) -> Double {
        guard !items.isEmpty else { return 50 }
        let now = Date()
        let total = Double(items.count)
        let dueCount = Double(items.filter { $0.nextReviewAt <= now }.count)
        let dueRatio = dueCount / total
        let avgMastery = items.reduce(0) { $0 + $1.mastery } / items.count
        let chronicCount = items.filter { $0.consecutiveMisses >= 4 }.count

        // Heavily decayed vault: returning student or major weak-area session
        if dueRatio > 0.70 && avgMastery < 40 { return 25 }
        // Lots due or multiple chronically stuck cards
        if dueRatio > 0.50 || chronicCount >= 3 { return 35 }
        // Well-mastered vault, few cards due — start close to flow
        if avgMastery >= 70 && dueRatio < 0.20 { return 65 }
        return 50
    }

    /// Maps an energy value to the corresponding FlowMode.
    /// Mirrors the switch in updateMode so initial mode is consistent.
    private func modeForEnergy(_ e: Double) -> FlowMode {
        switch e {
        case 80...:   return .flow
        case 40..<80: return .normal
        case 10..<40: return .review
        default:      return .recovery
        }
    }
}
