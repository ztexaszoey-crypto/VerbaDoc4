import Foundation
import SpriteKit
import UIKit

// MARK: - CapyAnimationState
//
// Phase 22 polish: procedural SKAction factory mapped to an FSM.
// The sandbox cannot generate art assets. Every state is a
// programmatic sequence of squash / stretch / rotate / scale.

enum CapyState: Equatable, Sendable {
    case idle
    case running
    case jumping
    case sliding
    case hit
    case celebrating
    case magnetPull
    case timeFreeze

    var isLocomoting: Bool {
        switch self {
        case .running, .jumping, .sliding, .magnetPull: return true
        default: return false
        }
    }
}

@MainActor
enum CapyAnimator {

    static func action(for state: CapyState) -> SKAction {
        switch state {
        case .idle:         return idleBreathing()
        case .running:     return runLoop()
        case .jumping:     return jumpSequence()
        case .sliding:     return slideSequence()
        case .hit:         return hitReaction()
        case .celebrating: return victoryDance()
        case .magnetPull:  return runLoop(intensity: 1.18)
        case .timeFreeze:  return idleBreathing(intensity: 0.55)
        }
    }

    static func apply(state: CapyState, to node: SKNode) {
        let rotationReset = SKAction.rotate(toAngle: 0, duration: 0.001)
        node.removeAction(forKey: "capy-anim")
        node.run(SKAction.group([rotationReset, action(for: state)]),
                 withKey: "capy-anim")
    }

    private static func idleBreathing(intensity: CGFloat = 1.0) -> SKAction {
        let s = SKAction.sequence([
            SKAction.scaleY(to: 1.0 + 0.03 * intensity, duration: 0.5),
            SKAction.scaleY(to: 1.0 - 0.03 * intensity, duration: 0.5),
        ])
        return SKAction.repeatForever(s)
    }

    private static func runLoop(intensity: CGFloat = 1.0) -> SKAction {
        // Phase 23 polish: stronger squash-and-stretch. Peak vertical
        // bounce now 1.28x (was 1.18) and trough 0.82x (was 0.94).
        // Phases are also slightly longer (0.08s peak vs 0.10s) so
        // the bounce reads as deliberate rather than jittery.
        let bounce = SKAction.sequence([
            SKAction.scaleY(to: 1.28 * intensity, duration: 0.08),
            SKAction.scaleY(to: 1.0,  duration: 0.10),
            SKAction.scaleY(to: 0.82 * intensity, duration: 0.10),
            SKAction.scaleY(to: 1.0,  duration: 0.12),
        ])
        let sway = SKAction.sequence([
            SKAction.rotate(toAngle:  0.05 * intensity, duration: 0.20),
            SKAction.rotate(toAngle: -0.05 * intensity, duration: 0.20),
        ])
        return SKAction.group([SKAction.repeatForever(bounce),
                               SKAction.repeatForever(sway)])
    }

    private static func jumpSequence() -> SKAction {
        // Phase 23 polish: anticipation crouch (1.30 x 0.74) at frame
        // zero, then takeoff stretch (0.84 x 1.28), then settle.
        // Reads as a real jump anticipation rather than a flat scale.
        SKAction.sequence([
            SKAction.scale(to: CGSize(width: 1.30, height: 0.74), duration: 0.06),
            SKAction.scale(to: CGSize(width: 0.84, height: 1.28), duration: 0.18),
            SKAction.scale(to: CGSize(width: 1.00, height: 1.00), duration: 0.14),
        ])
    }

    private static func slideSequence() -> SKAction {
        SKAction.sequence([
            SKAction.scale(to: CGSize(width: 1.15, height: 0.55), duration: 0.14),
            SKAction.wait(forDuration: 0.30),
            SKAction.scale(to: CGSize(width: 1.00, height: 1.00), duration: 0.10),
        ])
    }

    static func hitReaction() -> SKAction {
        SKAction.sequence([
            SKAction.group([
                SKAction.rotate(byAngle: 0.60, duration: 0.12),
                SKAction.colorize(with: UIColor.systemRed,
                                  colorBlendFactor: 0.55,
                                  duration: 0.05),
            ]),
            SKAction.group([
                SKAction.rotate(toAngle: 0, duration: 0.20),
                SKAction.colorize(with: .clear,
                                  colorBlendFactor: 0,
                                  duration: 0.20),
            ]),
        ])
    }

    static func victoryDance() -> SKAction {
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.6)
        let bounce = SKAction.sequence([
            SKAction.scaleY(to: 1.20, duration: 0.18),
            SKAction.scaleY(to: 1.00, duration: 0.18),
        ])
        return SKAction.group([spin, SKAction.repeatForever(bounce)])
    }
}
