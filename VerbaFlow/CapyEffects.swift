import Foundation
import SpriteKit
import UIKit
import SwiftUI

// MARK: - CapyEffects
//
// Phase 22 polish: programmatic particle bursts, camera shake, and
// the SwiftUI score-pop ViewModifier. None depend on a `.sks` asset.

@MainActor
enum CapyEffects {

    @discardableResult
    static func makeMelonBurst(at position: CGPoint,
                               parent: SKScene,
                               tint: UIColor = UIColor(red: 0.66, green: 0.83, blue: 0.24, alpha: 1)) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.position = position
        e.particleBirthRate = 240
        e.numParticlesToEmit = 28
        e.particleLifetime = 0.55
        e.particleLifetimeRange = 0.20
        e.particleSpeed = 160
        e.particleSpeedRange = 80
        e.emissionAngle = .pi * 2
        e.emissionAngleRange = .pi * 2
        e.particleAlpha = 1.0
        e.particleAlphaSpeed = -1.6
        e.particleScale = 0.18
        e.particleScaleRange = 0.08
        e.particleColor = tint
        e.particleColorBlendFactor = 1.0
        e.particleBlendMode = .add
        e.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.8),
            SKAction.removeFromParent(),
        ]))
        parent.addChild(e)
        return e
    }

    @discardableResult
    static func makeMagnetTrail(attachedTo node: SKNode,
                                tint: UIColor = .systemTeal) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleBirthRate = 80
        e.numParticlesToEmit = 0
        e.particleLifetime  = 0.35
        e.particleLifetimeRange = 0.10
        e.particleSpeed      = 30
        e.particleSpeedRange = 20
        e.particlePositionRange = CGVector(dx: 30, dy: 30)
        e.particleColor = tint
        e.particleColorBlendFactor = 0.7
        e.particleAlpha = 0.6
        e.particleAlphaSpeed = -1.4
        e.particleScale = 0.12
        e.particleBlendMode = .add
        node.addChild(e)
        return e
    }

    static func cameraShake(duration: TimeInterval = 0.30,
                            intensity: CGFloat = 6.0) -> SKAction {
        let stepCount = max(2, Int(duration / 0.04))
        var actions: [SKAction] = []
        for i in 0..<stepCount {
            let dx = (i % 2 == 0 ? intensity : -intensity) * CGFloat.random(in: 0.6...1.0)
            let dy = ((i + 1) % 2 == 0 ? intensity : -intensity) * CGFloat.random(in: 0.6...1.0)
            actions.append(SKAction.moveBy(x: dx, y: dy, duration: 0.04))
        }
        actions.append(SKAction.move(to: .zero, duration: 0.04))
        return SKAction.sequence(actions)
    }

    static let scorePop: ScorePopModifier = ScorePopModifier()
}

struct ScorePopModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                    scale = 1.18
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeOut(duration: 0.10)) {
                        scale = 1.0
                    }
                }
            }
    }
}
