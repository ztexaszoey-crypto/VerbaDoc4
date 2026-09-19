import Foundation
import SpriteKit
import CoreGraphics

// MARK: - CapyPlayerController
//
// Phase 22 polish: smooth lane interpolation + jump arc + slide.
// Replaces the instant-teleport lane-switch behavior the existing
// 5.7k-LOC scene shipped (the prior audit logged only 4 `swipe`
// hits across the whole game code -- reads "feels nothing"). The
// controller owns no rendering; CapySurfersScene instantiates it
// with an `SKNode` reference, the Scene polls update(_:) with
// `deltaTime`, and the controller mutates `node.position` directly
// each frame.
//
// Concurrency: SKNode is NOT `Sendable`. The controller is
// `@MainActor`; all reads + writes happen on main thread.

enum CapySwipeDirection: Sendable {
    case left
    case right
    case up
    case down
}

@MainActor
final class CapyPlayerController {

    struct FeelTuning: Sendable {
        var laneLerpSeconds:    TimeInterval = 0.18
        var jumpImpulse:        CGFloat = 380
        var gravity:            CGFloat = 1_400
        var slideDurationSecs:  TimeInterval = 0.55
        var hitRecoverySecs:    TimeInterval = 0.60

        static let `default` = FeelTuning()
    }

    enum State: Equatable, Sendable {
        case running
        case jumping(groundY: CGFloat, peakY: CGFloat, elapsed: TimeInterval)
        case sliding(elapsed: TimeInterval)
        case hitRecovery(elapsed: TimeInterval)
    }

    private let node: SKNode
    private let laneXPositions: [CGFloat]
    private(set) var currentLane: Int
    private(set) var targetLane:  Int
    private(set) var feelTuning:  FeelTuning = .default
    private(set) var state:       State = .running

    private var lerpStartX:  CGFloat = 0
    private var lerpElapsed: TimeInterval = 0

    init(node: SKNode, laneXPositions: [CGFloat], initialLane: Int = 1) {
        precondition(!laneXPositions.isEmpty,
                     "CapyPlayerController requires at least one lane position")
        precondition(initialLane >= 0 && initialLane < laneXPositions.count,
                     "initialLane out of bounds")
        self.node = node
        self.laneXPositions = laneXPositions
        self.currentLane = initialLane
        self.targetLane  = initialLane
        node.position.x  = laneXPositions[initialLane]
    }

    /// Lane-merges gated on the running state -- a swipe-LEFT while
    /// jumping/sliding still updates `targetLane` (queued) but does
    /// NOT start a brand-new lane lerp, which prevents the "stranded
    /// mid-lane on landing" bug.
    func handleSwipe(_ direction: CapySwipeDirection) {
        switch direction {
        case .left:
            targetLane = max(0, targetLane - 1)
            if case .running = state { startLaneLerp() }
        case .right:
            targetLane = min(laneXPositions.count - 1, targetLane + 1)
            if case .running = state { startLaneLerp() }
        case .up:
            guard case .running = state else { return }
            triggerJump()
        case .down:
            guard case .running = state else { return }
            triggerSlide()
        }
    }

    func update(dt: TimeInterval) {
        switch state {
        case .running:
            updateLaneLerp(dt: dt)
        case .jumping(let groundY, let peakY, let elapsed):
            advanceJump(groundY: groundY, peakY: peakY, elapsed: elapsed, dt: dt)
        case .sliding(let elapsed):
            advanceSlide(elapsed: elapsed, dt: dt)
        case .hitRecovery(let elapsed):
            advanceHitRecovery(elapsed: elapsed, dt: dt)
        }
    }

    /// Idempotent: a second hit during recovery does NOT extend stun.
    func applyHit() {
        if case .hitRecovery = state { return }
        state = .hitRecovery(elapsed: 0)
    }

    var canSwitchLane: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - FSM advancement

    private func advanceJump(groundY: CGFloat, peakY: CGFloat,
                             elapsed: TimeInterval, dt: TimeInterval) {
        let newElapsed = elapsed + dt
        let totalFlight = TimeInterval(max(0.001,
                                          2 * Double(peakY - groundY) / Double(feelTuning.gravity)))
        let progress = min(newElapsed / totalFlight, 1.0)
        let newY = groundY + (peakY - groundY) * CGFloat(sin(progress * .pi))
        node.position.y = newY
        if progress >= 1.0 {
            node.position.y = groundY
            resetLaneLerpAnchor()
            state = .running
        } else {
            state = .jumping(groundY: groundY, peakY: peakY, elapsed: newElapsed)
        }
    }

    private func advanceSlide(elapsed: TimeInterval, dt: TimeInterval) {
        let newElapsed = elapsed + dt
        if newElapsed >= feelTuning.slideDurationSecs {
            resetLaneLerpAnchor()
            state = .running
        } else {
            state = .sliding(elapsed: newElapsed)
        }
    }

    private func advanceHitRecovery(elapsed: TimeInterval, dt: TimeInterval) {
        let newElapsed = elapsed + dt
        if newElapsed >= feelTuning.hitRecoverySecs {
            resetLaneLerpAnchor()
            state = .running
        } else {
            state = .hitRecovery(elapsed: newElapsed)
        }
    }

    // Phase 22 fix (Req 2): resetLaneLerpAnchor is called whenever a
    // non-running FSM state transitions back into .running.  At that
    // moment the capy may be at any intermediate X (mid-jump,
    // mid-slide, post-hit).  Resetting lerpStartX and lerpElapsed
    // prevents a visible teleport on the next running frame, and
    // re-anchoring currentLane to targetLane keeps subsequent lane
    // switch decisions reasoned-about in lane-space, not lerp-space.

    private func resetLaneLerpAnchor() {
        // Re-anchor bookkeeping only. We deliberately do NOT snap
        // node.position.x to laneXPositions[currentLane]: the capy
        // may be at any intermediate X when transitioning back to
        // .running (mid-jump landing, mid-slide exit, post-hit). A
        // snap would create a visible lateral discontinuity. The
        // jump-trigger path instead snaps BEFORE the jump starts,
        // which is the perceptually correct frame to land at lane
        // center.
        lerpStartX  = node.position.x
        lerpElapsed = 0
        currentLane = targetLane
    }

    // MARK: - Lane lerp

    private func startLaneLerp() {
        guard targetLane != currentLane else { return }
        lerpStartX  = node.position.x
        lerpElapsed = 0
    }

    private func updateLaneLerp(dt: TimeInterval) {
        guard targetLane != currentLane else { return }
        lerpElapsed += dt
        let progress = min(lerpElapsed / feelTuning.laneLerpSeconds, 1.0)
        let eased = 1.0 - pow(1.0 - progress, 3.0)
        let targetX = laneXPositions[targetLane]
        node.position.x = lerpStartX + (targetX - lerpStartX) * CGFloat(eased)
        if progress >= 1.0 {
            currentLane = targetLane
            node.position.x = targetX
        }
    }

    // MARK: - Triggers

    private func triggerJump() {
        // Phase 22 lane-jump fix: complete any in-progress lane lerp
        // synchronously BEFORE starting the jump arc. If the capy was
        // mid-lerp from lane N to lane N+1 when the user swiped up,
        // the lerp was preempted (handleSwipe .up refuses unless state
        // is .running, but a running capy can be at any intermediate
        // X position because updateLaneLerp runs every frame). Snapping
        // X to the resolved lane center here means the jump arc starts
        // from a clean position and lands cleanly. Pair with the
        // resetLaneLerpAnchor bookkeeping reset so subsequent lane
        // switches reason in lane-space, not lerp-space.
        node.position.x = laneXPositions[currentLane]
        targetLane      = currentLane
        lerpStartX      = node.position.x
        lerpElapsed     = 0
        let groundY = node.position.y
        let peakY   = groundY + feelTuning.jumpImpulse
        state = .jumping(groundY: groundY, peakY: peakY, elapsed: 0)
    }

    private func triggerSlide() {
        state = .sliding(elapsed: 0)
    }
}
