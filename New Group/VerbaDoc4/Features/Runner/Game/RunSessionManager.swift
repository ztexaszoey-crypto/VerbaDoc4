import Foundation
import Combine
import SwiftData

// MARK: - RunResult

struct RunResult: Equatable {
    let score:              Int
    let distance:           Int            // metres (distancePts / 10)
    let duration:           TimeInterval
    let isNewBestScore:     Bool
    let isNewBestDistance:  Bool
    let gatesAnswered:      Int
    let gatesCorrect:       Int
}

// MARK: - RunSessionManager
//
// Single source of truth for the runner's lifecycle and score state.
// Owns GameScene and ChallengeManager so both persist across SwiftUI rebuilds.
//
// Threading: @MainActor throughout.
//   GameScene.update() runs on the main thread (SpriteKit's contract),
//   so all callbacks from the scene are safe to call here directly.

@MainActor
final class RunSessionManager: ObservableObject {

    // MARK: - State machine

    enum RunState: Equatable {
        case lobby
        case countdown(Int)
        case running
        case complete(RunResult)

        static func == (lhs: RunState, rhs: RunState) -> Bool {
            switch (lhs, rhs) {
            case (.lobby,            .lobby):            return true
            case (.countdown(let a), .countdown(let b)): return a == b
            case (.running,          .running):          return true
            case (.complete(let a),  .complete(let b)):  return a == b
            default:                                     return false
            }
        }
    }

    // MARK: - Published

    @Published private(set) var state:          RunState = .lobby
    @Published private(set) var score:          Int      = 0
    @Published private(set) var distance:       Int      = 0   // metres
    @Published private(set) var multiplier:     Double   = 1.0
    @Published private(set) var timeElapsed:    TimeInterval = 0
    @Published private(set) var activeGateCard:    StudyItem? = nil
    @Published private(set) var activeGateChoices: [String]  = []

    // MARK: - Personal Bests (UserDefaults)

    @Published private(set) var bestScore:    Int
    @Published private(set) var bestDistance: Int

    private let bestScoreKey    = "runner.best.score"
    private let bestDistanceKey = "runner.best.distance"

    // MARK: - Scene + challenge (owned here — persist for this manager's lifetime)

    let scene: GameScene
    let challengeManager = ChallengeManager()

    // MARK: - Study items (set by VerbaRunnerView before startCountdown)

    private var studyItems:  [StudyItem]    = []
    private var saveContext: (() -> Void)?  = nil

    // MARK: - Callbacks set by VerbaRunnerView (keep engine logic out of the view)

    /// Called each time a gate is answered (correct: Bool).
    var onGateAnswered: ((Bool) -> Void)?

    // MARK: - Internals

    private var countdownValue: Int  = 3
    private var countdownTimer: Timer?
    private var runStartedAt:   Date?

    // MARK: - Init

    init() {
        bestScore    = UserDefaults.standard.integer(forKey: "runner.best.score")
        bestDistance = UserDefaults.standard.integer(forKey: "runner.best.distance")

        let s = GameScene(size: CGSize(width: 390, height: 844))
        s.scaleMode = .resizeFill
        self.scene = s

        s.onGameOver = { [weak self] in
            self?.handleGameOver()
        }
        s.onGateHit = { [weak self] in
            self?.handleGateHit()
        }
        s.onScoreUpdate = { [weak self] score, metres, mult in
            guard let self else { return }
            self.score      = score
            self.distance   = metres
            self.multiplier = mult

            // Keep engine-mode game parameters in sync (≤O(1) per frame)
            let snapshot = self.challengeManager.engineSnapshot
            self.scene.engineSpeedMultiplier = CGFloat(GameBridge.speedMultiplier(for: snapshot))
            self.scene.engineIntervalScale   = CGFloat(GameBridge.spawnIntervalScale(for: snapshot))

            // Queue a gate obstacle if the distance threshold is met
            if self.challengeManager.checkAndQueueGate(distance: metres) {
                self.scene.pendingGate = true
            }
        }
        s.onTimeUpdate = { [weak self] elapsed in
            self?.timeElapsed = elapsed
        }
    }

    // MARK: - Study item injection

    /// Called by VerbaRunnerView before startCountdown so items and save closure
    /// are ready when beginRun() kicks off the engine session.
    func setStudyItems(_ items: [StudyItem], saveContext: @escaping () -> Void) {
        self.studyItems  = items
        self.saveContext = saveContext
    }

    // MARK: - Lifecycle

    func startCountdown() {
        countdownTimer?.invalidate()
        scene.resetRun()
        countdownValue = 3
        state = .countdown(3)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                self.countdownValue -= 1
                if self.countdownValue > 0 {
                    HapticManager.selection()
                    self.state = .countdown(self.countdownValue)
                } else {
                    timer.invalidate()
                    HapticManager.impact()
                    self.beginRun()
                }
            }
        }
    }

    private func beginRun() {
        score        = 0
        distance     = 0
        multiplier   = 1.0
        timeElapsed  = 0
        runStartedAt = Date()
        state        = .running
        scene.startRun()
        // Start SRS engine session with whatever items are available.
        // If empty, gates simply never fire (pure runner mode).
        challengeManager.startSession(from: studyItems)
    }

    private func handleGameOver() {
        countdownTimer?.invalidate()
        scene.stopRun()

        let duration   = runStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let (gatesAnswered, gatesCorrect) = challengeManager.endSession()

        let isNewScore = score    > bestScore
        let isNewDist  = distance > bestDistance

        if isNewScore {
            bestScore = score
            UserDefaults.standard.set(score, forKey: bestScoreKey)
        }
        if isNewDist {
            bestDistance = distance
            UserDefaults.standard.set(distance, forKey: bestDistanceKey)
        }

        if isNewScore || isNewDist {
            HapticManager.success()
        } else {
            HapticManager.impact()
        }

        state = .complete(RunResult(
            score:             score,
            distance:          distance,
            duration:          duration,
            isNewBestScore:    isNewScore,
            isNewBestDistance: isNewDist,
            gatesAnswered:     gatesAnswered,
            gatesCorrect:      gatesCorrect
        ))
    }

    // MARK: - Gate handling

    private func handleGateHit() {
        guard let result = challengeManager.activateGate(atDistance: distance) else { return }
        activeGateCard    = result.card
        activeGateChoices = result.choices
        // Scene is already paused by GameScene (stopRun called before onGateHit fires)
    }

    /// Called by VerbaRunnerView when the player taps an answer in QuestionOverlayView.
    func submitGateAnswer(correct: Bool) {
        guard let card = activeGateCard else { return }

        challengeManager.processGateAnswer(
            correct: correct,
            card:    card,
            save:    saveContext ?? {}
        )

        onGateAnswered?(correct)
        activeGateCard    = nil
        activeGateChoices = []
        scene.resumeRun()
    }

    // MARK: - Navigation

    func replay() {
        _ = challengeManager.endSession()
        activeGateCard = nil
        startCountdown()
    }

    func exitToLobby() {
        countdownTimer?.invalidate()
        challengeManager.endSession()
        scene.stopRun()
        scene.resetRun()
        activeGateCard    = nil
        activeGateChoices = []
        state = .lobby
    }
}
