import SpriteKit
import UIKit

// MARK: - CapyWorldAmbient
//
// Phase 24 polish: continuous per-world ambient particle emitters
// attached to the scene on buildWorld(). Each CapyWorld picks a
// distinct ambient palette (campus = leaf-green, library = parchment,
// science = mint-glow, space = starlight) with different emission
// rates and particle scales so the air visibly differs across worlds.
// SKEmitterNode obeys scene.speed automatically so the ambient
// particles freeze during the hit-slowmo window already wired in
// CapySurfersScene.runCameraShakeOnHit.

enum CapyWorldAmbient {

    /// Single ambient emitter for whichever world the scene is in.
    /// Attached as a scene-child so particles drift independently
    /// of capy motion (targetNode defaults to nil = scene world-space).
    /// Re-calling buildWorld() tears down the previous emitter by name.
    static func attach(to scene: SKScene, world: CapyWorld) {
        scene.children
            .compactMap { $0 as? SKEmitterNode }
            .filter { $0.name?.hasPrefix("ambient-") ?? false }
            .forEach { $0.removeFromParent() }
        let e = makeEmitter(for: world, frame: scene.size)
        e.name = "ambient-\(world.rawValue)"
        e.zPosition = -10
        scene.addChild(e)
    }

    private static func makeEmitter(for world: CapyWorld, frame: CGSize) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleBirthRate    = 14
        e.numParticlesToEmit   = 0
        e.particleLifetime     = 4.0
        e.particleLifetimeRange = 1.5
        e.particleSpeed        = 18
        e.particleSpeedRange   = 12
        e.emissionAngle        = .pi / 2
        e.emissionAngleRange   = .pi / 4
        e.particleAlpha        = 0.55
        e.particleAlphaSpeed   = -0.10
        e.particleScale        = 0.10
        e.particleScaleRange   = 0.06
        e.particleColorBlendFactor = 0.85
        e.particleBlendMode    = .add
        e.targetNode           = nil
        switch world {
        case .campus:
            e.particleColor      = UIColor(red: 0.45, green: 0.74, blue: 0.32, alpha: 1)
            e.particleBirthRate  = 10
            e.particleScale      = 0.14
        case .library:
            e.particleColor      = UIColor(red: 0.90, green: 0.85, blue: 0.55, alpha: 1)
            e.particleBirthRate  = 16
            e.particleScale      = 0.11
        case .science:
            e.particleColor      = UIColor(red: 0.40, green: 0.92, blue: 0.78, alpha: 1)
            e.particleBirthRate  = 18
            e.particleScale      = 0.09
        case .space:
            e.particleColor      = UIColor(red: 1.0,  green: 0.98, blue: 0.92, alpha: 1)
            e.particleBirthRate  = 22
            e.particleScale      = 0.05
        }
        // Particle-position range is a CGVector (SpriteKit uses dx/dy,
        // not width/height) — a CGSize won't compile here. dx = horizontal
        // spread of emit points, dy = vertical spread (6 px above ground).
        let emitArea = CGVector(dx: frame.width * 1.2, dy: 6)
        e.particlePositionRange = emitArea
        e.position = CGPoint(x: frame.width / 2, y: 0)
        return e
    }
}
