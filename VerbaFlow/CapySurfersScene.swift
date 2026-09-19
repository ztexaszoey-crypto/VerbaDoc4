import SpriteKit
import UIKit

// MARK: - CapySurfersScene
//
// Full redesign: endless lane-runner set in a capybara wetland/swamp.
// Lily pads + reeds + water instead of the old city-night track.
// Energy bar drains over time; when empty the scene pauses and posts
// .capyRefuelTriggered so the existing RefuelOverlay in
// CapySurfersGameView can serve a quiz question from CapySurfersState.
// Hitting an obstacle without a shield ends the run.
//
// Keeps the same integration contract as before:
//   - surfersState: CapySurfersState (XP, energy/juice, shield, coins)
//   - Notifications: .capyRestart / .capyResume / .capyRefuelTriggered
//   - Swipe controls: left / right / up (jump) / down (duck-slide)

enum CapyObstacleType: String, CaseIterable {
    case log        // duck-under
    case rock       // dodge sideways
    case reedWall   // full-lane block, must switch lanes
    case gator      // full-lane block, must jump
}

final class CapySurfersScene: SKScene {

    weak var surfersState: CapySurfersState?

    // ── Layout ───────────────────────────────────────────────────
    private var horizonY:  CGFloat { size.height * 0.60 }
    private var playerY:   CGFloat { size.height * 0.22 }
    private var currentLane = 1   // 0 left / 1 center / 2 right
    private let laneSpread: CGFloat = 110

    private func laneX(_ lane: Int) -> CGFloat {
        size.width / 2 + CGFloat(lane - 1) * laneSpread
    }

    private func perspScale(y: CGFloat) -> CGFloat {
        let t = (y - playerY) / (horizonY - playerY)
        return max(0.14, min(1.0, 1.0 - t * 0.76))
    }

    // ── Player controller ───────────────────────────────────────
    private var playerController: CapyPlayerController?
    private var lastAnimState: CapyState = .idle
    private var capy: SKNode!
    private var capyBody: SKShapeNode!
    private var capyShadow: SKShapeNode!
    private var shieldNode: SKShapeNode?

    // ── Run state ────────────────────────────────────────────────
    private var gameSpeed: CGFloat = 260
    private var isRunning = true
    private var distanceMM: Double = 0
    private var lastTime: TimeInterval = 0
    private var diffTimer: Double = 0
    private var obstacleTimer: Double = 0
    private var coinTimer: Double = 0
    private var lastDistanceMilestone: Int = -1

    // ── Physics categories ───────────────────────────────────────
    let catCapy: UInt32 = 1 << 0
    let catObstacle: UInt32 = 1 << 1
    let catCoin: UInt32 = 1 << 2
    let catShieldPickup: UInt32 = 1 << 3

    convenience init(state: CapySurfersState) {
        self.init()
        self.surfersState = state
    }

    // MARK: - VerbaDoc brand palette
    // Matches the app's cream/forest identity instead of a neon swamp
    // — the single biggest cheap win for "premium" over "kids game".
    private let paletteCream    = SKColor(red: 0.96, green: 0.96, blue: 0.93, alpha: 1) // #F5F5EC
    private let paletteForest   = SKColor(red: 0.09, green: 0.20, blue: 0.13, alpha: 1) // #173223
    private let paletteLeaf     = SKColor(red: 0.30, green: 0.48, blue: 0.34, alpha: 1) // muted leafy green
    private let paletteLime     = SKColor(red: 0.55, green: 0.78, blue: 0.42, alpha: 1) // soft lime accent
    private let paletteWater    = SKColor(red: 0.62, green: 0.74, blue: 0.70, alpha: 1) // desaturated sage-blue
    private let paletteSand     = SKColor(red: 0.82, green: 0.77, blue: 0.63, alpha: 1) // warm beige bank

    override func didMove(to view: SKView) {
        backgroundColor = paletteCream
        physicsWorld.gravity = CGVector(dx: 0, dy: -24)
        setupSwipes(view)
        setupNotifications()

        let cam = SKCameraNode()
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        self.camera = cam
        addChild(cam)

        buildWorld()
        buildCapybara()
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        view.gestureRecognizers?.removeAll()
    }

    // MARK: - World: swamp

    private func buildWorld() {
        buildSky()
        buildBackgroundReeds()
        buildWaterTrack()
    }

    private func buildSky() {
        // Base cream sky — no more saturated green flat-fill.
        let sky = SKSpriteNode(color: paletteCream, size: CGSize(width: size.width, height: size.height))
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -30
        addChild(sky)

        // Faux vertical gradient: stacked bands, each a hair darker/
        // cooler toward the horizon. Cheap "premium" depth cue with
        // zero art — flat single-color skies read as placeholder.
        let bandCount = 6
        for i in 0..<bandCount {
            let t = CGFloat(i) / CGFloat(bandCount - 1)
            let bandY = horizonY + (size.height - horizonY) * (1 - t)
            let band = SKSpriteNode(
                color: SKColor(
                    red: paletteCream.redValue - 0.04 * t,
                    green: paletteCream.greenValue - 0.02 * t,
                    blue: paletteCream.blueValue + 0.03 * t,
                    alpha: 0.5
                ),
                size: CGSize(width: size.width, height: (size.height - horizonY) / CGFloat(bandCount) + 4)
            )
            band.position = CGPoint(x: size.width / 2, y: bandY)
            band.zPosition = -29
            addChild(band)
        }

        // Sun — softened, desaturated toward lime rather than neon yellow.
        let sun = SKShapeNode(circleOfRadius: 26)
        sun.fillColor = SKColor(red: 0.98, green: 0.90, blue: 0.62, alpha: 0.55)
        sun.strokeColor = .clear
        sun.position = CGPoint(x: size.width * 0.78, y: horizonY + size.height * 0.24)
        sun.zPosition = -28
        addChild(sun)
        let sunHalo = SKShapeNode(circleOfRadius: 40)
        sunHalo.fillColor = sun.fillColor.withAlphaComponent(0.18)
        sunHalo.strokeColor = .clear
        sunHalo.position = sun.position
        sunHalo.zPosition = -29
        addChild(sunHalo)

        // Distant tree silhouettes — forest palette, two-tone for depth
        // (a darker back layer + lighter front layer per tree reads as
        // "shaded foliage" instead of a flat blob).
        for i in 0..<7 {
            let x = size.width * CGFloat(i) / 6.0
            let h = CGFloat.random(in: 40...90)
            let trunk = SKShapeNode(rectOf: CGSize(width: 6, height: h * 0.4))
            trunk.fillColor = paletteForest.withAlphaComponent(0.45)
            trunk.strokeColor = .clear
            trunk.position = CGPoint(x: x, y: horizonY + h * 0.15)
            trunk.zPosition = -24
            addChild(trunk)

            let canopyBack = SKShapeNode(ellipseOf: CGSize(width: h * 0.9, height: h * 0.6))
            canopyBack.fillColor = paletteForest.withAlphaComponent(0.42)
            canopyBack.strokeColor = .clear
            canopyBack.position = CGPoint(x: x, y: horizonY + h * 0.42)
            canopyBack.zPosition = -23
            addChild(canopyBack)

            let canopyFront = SKShapeNode(ellipseOf: CGSize(width: h * 0.62, height: h * 0.4))
            canopyFront.fillColor = paletteLeaf.withAlphaComponent(0.40)
            canopyFront.strokeColor = .clear
            canopyFront.position = CGPoint(x: x - h * 0.08, y: horizonY + h * 0.48)
            canopyFront.zPosition = -22
            addChild(canopyFront)
        }

        // Horizon fog band — blends midground into background so the
        // tree line doesn't have a hard "cardboard cutout" edge.
        let fog = SKSpriteNode(color: paletteCream.withAlphaComponent(0.35), size: CGSize(width: size.width, height: 46))
        fog.position = CGPoint(x: size.width / 2, y: horizonY + 6)
        fog.zPosition = -21
        addChild(fog)
    }

    private func buildBackgroundReeds() {
        // Reed clusters framing both sides near the player, swamp-style
        addReedCluster(xLeft: -10, xRight: laneX(0) - 75, yBase: horizonY - 20)
        addReedCluster(xLeft: laneX(2) + 75, xRight: size.width + 10, yBase: horizonY - 20)
    }

    private func addReedCluster(xLeft: CGFloat, xRight: CGFloat, yBase: CGFloat) {
        var x = xLeft
        while x < xRight {
            let h = CGFloat.random(in: 26...54)
            let reed = SKShapeNode(rectOf: CGSize(width: 3, height: h), cornerRadius: 1.5)
            reed.fillColor = paletteLeaf.withAlphaComponent(0.82)
            reed.strokeColor = .clear
            reed.position = CGPoint(x: x, y: yBase + h / 2)
            reed.zPosition = -12
            addChild(reed)
            reed.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(byAngle: 0.06, duration: 0.9),
                SKAction.rotate(byAngle: -0.06, duration: 0.9)
            ])))
            x += CGFloat.random(in: 8...16)
        }
    }

    private func buildWaterTrack() {
        // Warm sand bank instead of a flat muddy-brown block.
        let ground = SKSpriteNode(color: paletteSand, size: CGSize(width: size.width * 1.4, height: size.height))
        ground.position = CGPoint(x: size.width / 2, y: size.height * 0.28)
        ground.zPosition = -8
        addChild(ground)

        // Subtle darker band along the near edge of the sand for
        // grounding contact-shadow feel, rather than a hard flat plane.
        let groundShade = SKSpriteNode(
            color: paletteSand.withAlphaComponent(0.5),
            size: CGSize(width: size.width * 1.4, height: 60)
        )
        groundShade.color = SKColor(
            red: paletteSand.redValue * 0.82, green: paletteSand.greenValue * 0.82,
            blue: paletteSand.blueValue * 0.82, alpha: 1
        )
        groundShade.position = CGPoint(x: size.width / 2, y: playerY - 6)
        groundShade.zPosition = -7.5
        addChild(groundShade)

        // Water track — desaturated sage-blue, matches brand instead
        // of a saturated teal-cyan swamp.
        let trackW: CGFloat = 340
        let water = SKSpriteNode(color: paletteWater, size: CGSize(width: trackW, height: size.height * 0.45))
        water.position = CGPoint(x: size.width / 2, y: size.height * 0.28)
        water.zPosition = -7
        addChild(water)

        // Two-tone water shading: a lighter center band fakes a soft
        // gradient/reflection strip instead of one flat color.
        let waterHighlight = SKSpriteNode(
            color: paletteWater.withAlphaComponent(0.0),
            size: CGSize(width: trackW * 0.5, height: size.height * 0.45)
        )
        waterHighlight.color = SKColor(
            red: min(paletteWater.redValue + 0.08, 1), green: min(paletteWater.greenValue + 0.06, 1),
            blue: min(paletteWater.blueValue + 0.05, 1), alpha: 0.5
        )
        waterHighlight.position = water.position
        waterHighlight.zPosition = -6.8
        addChild(waterHighlight)

        // Water shimmer lines
        spawnScrollingRipples()

        // Lily pads scattered along the lanes for flavor
        spawnLilyPadDecor()
    }

    private func spawnScrollingRipples() {
        let container = SKNode()
        container.zPosition = -5
        addChild(container)
        for i in 0..<12 {
            let t = CGFloat(i) / 12.0
            let y = horizonY + (playerY - horizonY) * t
            let w = 20 + 80 * t
            let ripple = SKShapeNode(ellipseOf: CGSize(width: w, height: 4))
            ripple.strokeColor = SKColor.white.withAlphaComponent(0.25)
            ripple.fillColor = .clear
            ripple.lineWidth = 1.5
            ripple.position = CGPoint(x: size.width / 2, y: y)
            container.addChild(ripple)
        }
        let move = SKAction.moveBy(x: 0, y: -(playerY - horizonY), duration: 1.1)
        let reset = SKAction.moveTo(y: 0, duration: 0)
        container.run(SKAction.repeatForever(SKAction.sequence([move, reset])))
    }

    private func spawnLilyPadDecor() {
        for lane in [0, 2] {
            let x = laneX(lane) + CGFloat.random(in: -20...20)
            let pad = SKShapeNode(ellipseOf: CGSize(width: 26, height: 14))
            pad.fillColor = paletteLeaf.withAlphaComponent(0.78)
            pad.strokeColor = paletteForest.withAlphaComponent(0.3)
            pad.lineWidth = 1
            pad.position = CGPoint(x: x, y: horizonY - 6)
            pad.zPosition = -4
            addChild(pad)
        }
    }

    // MARK: - Capybara (redesigned, swamp-cute)

    private func buildCapybara() {
        let skin = surfersState?.equippedSkin ?? CapySkin.all[0]
        let bc = SKColor(red: skin.bodyColor.r, green: skin.bodyColor.g, blue: skin.bodyColor.b, alpha: 1)
        let ac = SKColor(red: skin.accentColor.r, green: skin.accentColor.g, blue: skin.accentColor.b, alpha: 1)
        let lt = SKColor(
            red: min(skin.bodyColor.r + 0.16, 1),
            green: min(skin.bodyColor.g + 0.12, 1),
            blue: min(skin.bodyColor.b + 0.08, 1),
            alpha: 1
        )
        let ink = SKColor(red: 0.12, green: 0.08, blue: 0.05, alpha: 1)

        capy = SKNode()
        capy.position = CGPoint(x: laneX(1), y: playerY + 24)
        capy.zPosition = 10

        playerController = CapyPlayerController(
            node: capy,
            laneXPositions: [laneX(0), laneX(1), laneX(2)],
            initialLane: 1
        )
        lastAnimState = .running

        addChild(capy)

        // Ground-anchored contact shadow. Stays at ground Y regardless
        // of jump height and shrinks/fades as Capy rises — this single
        // element does more for "feels grounded, not floating cutout"
        // than any amount of body shading.
        capyShadow = SKShapeNode(ellipseOf: CGSize(width: 46, height: 12))
        capyShadow.fillColor = paletteForest.withAlphaComponent(0.22)
        capyShadow.strokeColor = .clear
        capyShadow.position = CGPoint(x: capy.position.x, y: playerY)
        capyShadow.zPosition = 9
        addChild(capyShadow)

        // Body — chunkier, rounder for the "cute swamp capybara" look
        capyBody = SKShapeNode(ellipseOf: CGSize(width: 60, height: 34))
        capyBody.fillColor = bc
        capyBody.strokeColor = ac
        capyBody.lineWidth = 2.5
        capy.addChild(capyBody)

        // Belly-side shade + back-side rim highlight layered onto the
        // flat ellipse — the cheapest possible fake-lighting pass that
        // makes a shape read as "modeled" instead of "flat sticker".
        let bodyShade = SKShapeNode(ellipseOf: CGSize(width: 58, height: 16))
        bodyShade.fillColor = SKColor(red: bc.redValue * 0.80, green: bc.greenValue * 0.80, blue: bc.blueValue * 0.80, alpha: 0.55)
        bodyShade.strokeColor = .clear
        bodyShade.position = CGPoint(x: 0, y: -9)
        bodyShade.zPosition = capyBody.zPosition + 0.1
        capy.addChild(bodyShade)

        let bodyRim = SKShapeNode(ellipseOf: CGSize(width: 54, height: 14))
        bodyRim.fillColor = lt.withAlphaComponent(0.35)
        bodyRim.strokeColor = .clear
        bodyRim.position = CGPoint(x: -2, y: 10)
        bodyRim.zPosition = capyBody.zPosition + 0.1
        capy.addChild(bodyRim)

        CapyAnimator.apply(state: .running, to: capyBody)

        // Head
        let head = SKShapeNode(ellipseOf: CGSize(width: 30, height: 26))
        head.fillColor = bc
        head.strokeColor = ac
        head.lineWidth = 2
        head.position = CGPoint(x: 23, y: 16)
        capy.addChild(head)

        // Snout
        let snout = SKShapeNode(rectOf: CGSize(width: 20, height: 12), cornerRadius: 5)
        snout.fillColor = lt
        snout.strokeColor = .clear
        snout.position = CGPoint(x: 33, y: 10)
        capy.addChild(snout)

        // Nostrils
        for (nx, ny) in [(30.0, 10.0), (36.0, 10.0)] {
            let n = SKShapeNode(circleOfRadius: 2.2)
            n.fillColor = ink
            n.strokeColor = .clear
            n.position = CGPoint(x: nx, y: ny)
            capy.addChild(n)
        }

        // Eyes with shine
        for (ex, ey) in [(17.0, 22.0), (27.0, 22.0)] {
            let eye = SKShapeNode(circleOfRadius: 4.0)
            eye.fillColor = ink
            eye.strokeColor = .clear
            eye.position = CGPoint(x: ex, y: ey)
            capy.addChild(eye)
            let shine = SKShapeNode(circleOfRadius: 1.5)
            shine.fillColor = .white
            shine.strokeColor = .clear
            shine.position = CGPoint(x: ex + 1.3, y: ey + 1.3)
            capy.addChild(shine)
        }

        // Ears
        for (ex, ey): (CGFloat, CGFloat) in [(15, 29), (24, 31)] {
            let ear = SKShapeNode(ellipseOf: CGSize(width: 10, height: 12))
            ear.fillColor = bc
            ear.strokeColor = .clear
            ear.position = CGPoint(x: ex, y: ey)
            capy.addChild(ear)
            ear.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(byAngle: 0.10, duration: 0.18),
                SKAction.rotate(byAngle: -0.10, duration: 0.18)
            ])))
        }

        // Smile
        let sp = CGMutablePath()
        sp.addArc(center: CGPoint(x: 33, y: 7), radius: 4.5, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
        let smile = SKShapeNode(path: sp)
        smile.strokeColor = ink
        smile.lineWidth = 2
        smile.lineCap = .round
        capy.addChild(smile)

        // Belly highlight
        let hl = SKShapeNode(ellipseOf: CGSize(width: 28, height: 10))
        hl.fillColor = SKColor.white.withAlphaComponent(0.16)
        hl.strokeColor = .clear
        hl.position = CGPoint(x: -4, y: 8)
        capy.addChild(hl)

        // Running legs — 4 staggered
        for (xOff, delay): (CGFloat, Double) in [(-11, 0), (-4, 0.14), (4, 0.28), (11, 0.42)] {
            let leg = SKShapeNode(rectOf: CGSize(width: 7, height: 13), cornerRadius: 3)
            leg.fillColor = SKColor(
                red: bc.redValue * 0.88, green: bc.greenValue * 0.88, blue: bc.blueValue * 0.88, alpha: 1
            )
            leg.strokeColor = .clear
            leg.position = CGPoint(x: xOff, y: -18)
            capy.addChild(leg)
            let run = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 4, duration: 0.11),
                SKAction.moveBy(x: 0, y: -4, duration: 0.11)
            ])
            leg.run(SKAction.repeatForever(SKAction.sequence([SKAction.wait(forDuration: delay), run])))
        }

        // Breathe
        capyBody.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleY(to: 1.04, duration: 0.55),
            SKAction.scaleY(to: 0.97, duration: 0.55)
        ])))

        // Physics
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 52, height: 34))
        pb.allowsRotation = false
        pb.linearDamping = 0.5
        pb.categoryBitMask = catCapy
        pb.contactTestBitMask = catObstacle | catCoin | catShieldPickup
        pb.collisionBitMask = 0
        capy.physicsBody = pb
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard isRunning else { return }
        let dt = lastTime == 0 ? 0.016 : min(currentTime - lastTime, 0.05)
        lastTime = currentTime

        rampSpeed(dt)
        spawnObstacles(dt)
        spawnCoins(dt)
        updateDistance(dt)
        drainEnergy(dt)

        if let ctrl = playerController {
            ctrl.update(dt: dt)
            currentLane = ctrl.currentLane
        }
        updateCapyShadow()
        syncAnimState()
        checkDistanceMilestoneIfNeeded()
    }

    private func rampSpeed(_ dt: Double) {
        diffTimer += dt
        let warmup = CGFloat(min(diffTimer / 12.0, 1.0))
        let distanceRamp = CGFloat(min(distanceMM / 5000.0, 1.0))
        let base: CGFloat = 260
        let warmupBoost: CGFloat = 160
        let runBoost: CGFloat = 600
        gameSpeed = base + warmup * warmupBoost + distanceRamp * runBoost
    }

    /// Energy bar drain. When it hits 0, pause the run and post
    /// .capyRefuelTriggered so the existing RefuelOverlay serves a
    /// quiz question from CapySurfersState. Mirrors the previous
    /// drainPlayerEnergy contract exactly.
    private func drainEnergy(_ dt: Double) {
        guard let state = surfersState else { return }
        let depleted = state.drainEnergy(dt: dt, speed: gameSpeed)
        if depleted { return } // state machine already paused us
        if state.energy < 25 {
            state.flashLowJuice()
        }
    }

    private func updateDistance(_ dt: Double) {
        distanceMM += Double(gameSpeed) * dt
        surfersState?.addDistance(1)
    }

    // MARK: - Obstacles

    private func spawnObstacles(_ dt: Double) {
        obstacleTimer += dt
        let interval = max(0.9, 2.3 - diffTimer * 0.004)
        guard obstacleTimer >= interval else { return }
        obstacleTimer = 0

        let lane = Int.random(in: 0...2)
        spawnObstacle(lane: lane)
        if diffTimer > 22 && Bool.random() {
            let other = (lane + 1 + Int.random(in: 0...1)) % 3
            if other != lane { spawnObstacle(lane: other) }
        }
    }

    private func spawnObstacle(lane: Int) {
        let types: [CapyObstacleType] = diffTimer < 8 ? [.rock] : CapyObstacleType.allCases
        guard let type = types.randomElement() else { return }
        let node = makeObstacle(type: type)

        let sc = perspScale(y: horizonY)
        node.setScale(sc)
        node.position = CGPoint(x: laneX(lane) * sc + size.width / 2 * (1 - sc), y: horizonY)
        node.zPosition = 1
        node.name = "obstacle"
        addChild(node)

        let endSc = perspScale(y: playerY + 18)
        let dur = Double((playerY - horizonY) / -gameSpeed) * 1.5
        let move = SKAction.move(to: CGPoint(x: laneX(lane), y: playerY + 18), duration: dur)
        let scale = SKAction.scale(to: endSc, duration: dur)
        let hit = SKAction.run { [weak self] in self?.obstacleHitCheck(node: node, lane: lane) }
        node.run(SKAction.sequence([SKAction.group([move, scale]), hit, SKAction.removeFromParent()]))
    }

    private func makeObstacle(type: CapyObstacleType) -> SKNode {
        let node = SKNode()

        // Contact shadow under every obstacle — same trick as Capy's:
        // without it, obstacles read as pasted-on stickers rather than
        // objects sitting on the track.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 44, height: 10))
        shadow.fillColor = paletteForest.withAlphaComponent(0.16)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -6)
        shadow.zPosition = -1
        node.addChild(shadow)

        switch type {
        case .log:
            // Floating log — duck under. Warm wood tone tuned toward
            // the brand's warm-neutral end rather than raw brown.
            let log = SKShapeNode(rectOf: CGSize(width: 58, height: 16), cornerRadius: 8)
            log.fillColor = SKColor(red: 0.48, green: 0.36, blue: 0.24, alpha: 1)
            log.strokeColor = paletteForest.withAlphaComponent(0.7)
            log.lineWidth = 2
            log.position = CGPoint(x: 0, y: 10)
            node.addChild(log)
            let logHighlight = SKShapeNode(rectOf: CGSize(width: 54, height: 5), cornerRadius: 2.5)
            logHighlight.fillColor = SKColor(red: 0.60, green: 0.48, blue: 0.34, alpha: 0.6)
            logHighlight.strokeColor = .clear
            logHighlight.position = CGPoint(x: 0, y: 15)
            node.addChild(logHighlight)
            for ry in [-3.0, 2.0, 7.0] {
                let ring = SKShapeNode(rectOf: CGSize(width: 3, height: 12), cornerRadius: 1)
                ring.fillColor = SKColor(red: 0.36, green: 0.26, blue: 0.16, alpha: 0.6)
                ring.strokeColor = .clear
                ring.position = CGPoint(x: CGFloat(ry) * 5, y: 10)
                node.addChild(ring)
            }
            let arrow = makeDownArrow(size: 12)
            arrow.position = CGPoint(x: 0, y: 22)
            node.addChild(arrow)

        case .rock:
            // Mossy rock — dodge sideways. Neutral warm-gray + lime moss.
            let rock = SKShapeNode(ellipseOf: CGSize(width: 30, height: 24))
            rock.fillColor = SKColor(red: 0.55, green: 0.54, blue: 0.48, alpha: 1)
            rock.strokeColor = paletteForest.withAlphaComponent(0.55)
            rock.lineWidth = 2
            node.addChild(rock)
            let rockHighlight = SKShapeNode(ellipseOf: CGSize(width: 14, height: 9))
            rockHighlight.fillColor = .white.withAlphaComponent(0.20)
            rockHighlight.strokeColor = .clear
            rockHighlight.position = CGPoint(x: 5, y: 7)
            node.addChild(rockHighlight)
            let moss = SKShapeNode(ellipseOf: CGSize(width: 14, height: 8))
            moss.fillColor = paletteLime.withAlphaComponent(0.85)
            moss.strokeColor = .clear
            moss.position = CGPoint(x: -4, y: 5)
            node.addChild(moss)

        case .reedWall:
            // Reed cluster spanning the lane — dodge sideways
            for i in 0..<5 {
                let h = CGFloat.random(in: 34...52)
                let reed = SKShapeNode(rectOf: CGSize(width: 4, height: h), cornerRadius: 2)
                reed.fillColor = paletteLeaf.withAlphaComponent(0.95)
                reed.strokeColor = .clear
                reed.position = CGPoint(x: CGFloat(i - 2) * 8, y: h / 2 - 10)
                node.addChild(reed)
            }

        case .gator:
            // Small gator silhouette — must jump. Deep forest tone so
            // it reads as "part of this world" rather than a clashing
            // saturated green.
            let body = SKShapeNode(ellipseOf: CGSize(width: 48, height: 18))
            body.fillColor = paletteForest.withAlphaComponent(0.9)
            body.strokeColor = paletteForest
            body.lineWidth = 2
            node.addChild(body)
            let bodyHighlight = SKShapeNode(ellipseOf: CGSize(width: 34, height: 6))
            bodyHighlight.fillColor = paletteLeaf.withAlphaComponent(0.4)
            bodyHighlight.strokeColor = .clear
            bodyHighlight.position = CGPoint(x: 0, y: 5)
            node.addChild(bodyHighlight)
            let snout = SKShapeNode(rectOf: CGSize(width: 20, height: 8), cornerRadius: 3)
            snout.fillColor = body.fillColor
            snout.strokeColor = .clear
            snout.position = CGPoint(x: 30, y: -2)
            node.addChild(snout)
            for tx in [-14.0, -6.0, 2.0, 10.0] {
                let spike = SKShapeNode(rectOf: CGSize(width: 4, height: 6), cornerRadius: 1)
                spike.fillColor = paletteForest
                spike.strokeColor = .clear
                spike.position = CGPoint(x: CGFloat(tx), y: 9)
                node.addChild(spike)
            }
        }

        let hitbox = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 30))
        hitbox.isDynamic = false
        hitbox.categoryBitMask = catObstacle
        hitbox.contactTestBitMask = catCapy
        node.physicsBody = hitbox
        return node
    }

    private func obstacleHitCheck(node: SKNode, lane: Int) {
        guard isRunning else { return }
        guard currentLane == lane else { return }
        if surfersState?.hasShield == true {
            surfersState?.hasShield = false
            shieldHit()
            return
        }
        playerController?.applyHit()
        runCameraShakeOnHit()
        HapticManager.impact(.heavy)
        playerCrashed()
    }

    // MARK: - Coins (renamed from melons; same collectible role)

    private func spawnCoins(_ dt: Double) {
        coinTimer += dt
        guard coinTimer >= 0.5 else { return }
        coinTimer = 0
        spawnCoinLine(lane: Int.random(in: 0...2))
    }

    private func spawnCoinLine(lane: Int) {
        let count = 3
        for i in 1...count {
            let t = CGFloat(i) / CGFloat(count + 1)
            let y = horizonY + (playerY - horizonY) * t
            let sc = perspScale(y: y) * 0.55
            let x = laneX(lane) * perspScale(y: y) + size.width / 2 * (1 - perspScale(y: y))
            let c = makeCoin()
            c.setScale(sc)
            c.position = CGPoint(x: x, y: y)
            c.name = "coin"
            c.zPosition = 2
            addChild(c)
            let dur = Double((playerY - y) / gameSpeed) * 1.5
            let move = SKAction.move(to: CGPoint(x: laneX(lane), y: playerY + 12), duration: dur + Double(i) * 0.05)
            let scale = SKAction.scale(to: perspScale(y: playerY + 12) * 0.55, duration: dur)
            let collect = SKAction.run { [weak self] in self?.collectCoinCheck(node: c, lane: lane) }
            c.run(SKAction.sequence([SKAction.group([move, scale]), collect, SKAction.removeFromParent()]))
        }
    }

    private func makeCoin() -> SKNode {
        let node = SKNode()
        // Soft glow behind the coin — cheap way to make a flat circle
        // read as "glinting collectible" instead of "yellow dot".
        let glow = SKShapeNode(circleOfRadius: 19)
        glow.fillColor = SKColor(red: 0.90, green: 0.78, blue: 0.42, alpha: 0.20)
        glow.strokeColor = .clear
        glow.zPosition = -1
        node.addChild(glow)
        let c = SKShapeNode(circleOfRadius: 13)
        c.fillColor = SKColor(red: 0.88, green: 0.72, blue: 0.32, alpha: 1) // desaturated warm gold
        c.strokeColor = SKColor(red: 0.62, green: 0.50, blue: 0.20, alpha: 1)
        c.lineWidth = 2
        node.addChild(c)
        let inner = SKShapeNode(circleOfRadius: 8)
        inner.fillColor = SKColor(red: 0.97, green: 0.88, blue: 0.60, alpha: 0.75)
        inner.strokeColor = .clear
        node.addChild(inner)
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 2.5, duration: 0.38),
            SKAction.moveBy(x: 0, y: -2.5, duration: 0.38)
        ])))
        let pb = SKPhysicsBody(circleOfRadius: 12)
        pb.isDynamic = false
        pb.categoryBitMask = catCoin
        pb.contactTestBitMask = catCapy
        node.physicsBody = pb
        return node
    }

    private func collectCoinCheck(node: SKNode, lane: Int) {
        guard isRunning, currentLane == lane else { return }
        let pickupPoint = node.position
        node.removeFromParent()
        surfersState?.collectMelon() // existing coin-tally hook on state
        CapyAudioEngine.shared.play(.coin)
        CapyEffects.makeMelonBurst(at: pickupPoint, parent: self)
        HapticManager.selection()

        let popup = SKNode()
        popup.position = CGPoint(x: laneX(lane), y: playerY + 38)
        popup.zPosition = 50
        let plusLbl = SKLabelNode(text: "+1")
        plusLbl.fontName = "SF-Pro-Rounded-Black"
        plusLbl.fontSize = 13
        plusLbl.fontColor = SKColor(red: 0.96, green: 0.80, blue: 0.12, alpha: 1)
        popup.addChild(plusLbl)
        addChild(popup)
        popup.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: CGFloat.random(in: -8...12), y: 38, duration: 0.45),
                SKAction.fadeOut(withDuration: 0.40)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Shield / protection pickup (simplified from old powerup roster)

    private func addShield() {
        shieldNode?.removeFromParent()
        let shield = SKShapeNode(circleOfRadius: 42)
        shield.fillColor = paletteLime.withAlphaComponent(0.16)
        shield.strokeColor = paletteLime.withAlphaComponent(0.85)
        shield.lineWidth = 3
        shield.zPosition = 20
        capy.addChild(shield)
        shieldNode = shield
        shield.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.5),
            SKAction.scale(to: 0.95, duration: 0.5)
        ])))
    }

    private func shieldHit() {
        shieldNode?.run(SKAction.sequence([
            SKAction.scale(to: 1.4, duration: 0.1),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))
        shieldNode = nil
    }

    // MARK: - Crash / game over

    private func playerCrashed() {
        guard isRunning else { return }
        isRunning = false
        HapticManager.impact(.heavy)
        capy.run(SKAction.sequence([
            SKAction.rotate(byAngle: .pi * 0.25, duration: 0.12),
            SKAction.moveBy(x: 0, y: -18, duration: 0.18),
            SKAction.rotate(byAngle: .pi, duration: 0.22),
            SKAction.wait(forDuration: 0.25)
        ])) {
            DispatchQueue.main.async { self.surfersState?.endRun() }
        }
        let burstColors: [SKColor] = [
            SKColor(red: 0.88, green: 0.72, blue: 0.32, alpha: 1), // gold, matches coins
            paletteWater,
            paletteLime
        ]
        for i in 0..<8 {
            let sizeR = CGFloat.random(in: 5...11)
            let shape = SKShapeNode(circleOfRadius: sizeR)
            shape.fillColor = burstColors[i % burstColors.count]
            shape.strokeColor = .clear
            shape.position = capy.position
            shape.zPosition = 50
            addChild(shape)
            shape.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -60...60), y: CGFloat.random(in: -40...60), duration: 0.55),
                    SKAction.fadeOut(withDuration: 0.55)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Controls

    private func setupSwipes(_ view: SKView) {
        for (dir, sel): (UISwipeGestureRecognizer.Direction, Selector) in [
            (.left, #selector(swipeLeft)),
            (.right, #selector(swipeRight)),
            (.up, #selector(swipeUp)),
            (.down, #selector(swipeDown))
        ] {
            let g = UISwipeGestureRecognizer(target: self, action: sel)
            g.direction = dir
            view.addGestureRecognizer(g)
        }
    }

    @objc private func swipeLeft() { handleInput(.left) }
    @objc private func swipeRight() { handleInput(.right) }
    @objc private func swipeUp() { handleInput(.up) }
    @objc private func swipeDown() { handleInput(.down) }

    private func handleInput(_ direction: CapySwipeDirection) {
        guard isRunning, !isPaused, let ctrl = playerController else { return }
        let preLane = ctrl.currentLane
        ctrl.handleSwipe(direction)
        HapticManager.selection()
        if (direction == .left || direction == .right), ctrl.currentLane != preLane {
            runLean()
        }
    }

    private func runLean() {
        let angle: CGFloat = {
            switch currentLane {
            case 0: return -0.11
            case 2: return 0.11
            default: return 0
            }
        }()
        let lean = SKAction.sequence([
            SKAction.rotate(toAngle: angle, duration: 0.08),
            SKAction.wait(forDuration: 0.10),
            SKAction.rotate(toAngle: 0, duration: 0.10)
        ])
        capyBody?.run(lean, withKey: "lean")
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onRestart), name: .capyRestart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onResume), name: .capyResume, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onRefuelTriggered), name: .capyRefuelTriggered, object: nil)
    }

    @objc private func onRestart() {
        removeAllChildren()
        removeAllActions()
        isRunning = true
        currentLane = 1
        gameSpeed = 260
        distanceMM = 0
        obstacleTimer = 0
        coinTimer = 0
        diffTimer = 0
        lastTime = 0
        shieldNode = nil
        lastDistanceMilestone = -1
        buildWorld()
        buildCapybara()
    }

    @objc private func onResume() {
        isRunning = true
        isPaused = false
    }

    @objc private func onRefuelTriggered() {
        // Energy hit 0 — pause the run. RefuelOverlay (existing view)
        // serves the next quiz question from CapySurfersState and
        // posts .capyResume once answered/countdown completes.
        isRunning = false
        isPaused = true
    }

    // MARK: - Small drawn helpers

    private func makeDownArrow(size: CGFloat) -> SKNode {
        let node = SKNode()
        let s = size / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s, y: s))
        path.addLine(to: CGPoint(x: 0, y: -s))
        path.addLine(to: CGPoint(x: s, y: s))
        let arrow = SKShapeNode(path: path)
        arrow.strokeColor = SKColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 0.9)
        arrow.lineWidth = 2
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.fillColor = .clear
        node.addChild(arrow)
        return node
    }
}

// MARK: - Color helper (kept isolated, no scene methods inside)

private extension SKColor {
    var redValue: CGFloat { var r: CGFloat = 0; getRed(&r, green: nil, blue: nil, alpha: nil); return r }
    var greenValue: CGFloat { var g: CGFloat = 0; getRed(nil, green: &g, blue: nil, alpha: nil); return g }
    var blueValue: CGFloat { var b: CGFloat = 0; getRed(nil, green: nil, blue: &b, alpha: nil); return b }
}

// MARK: - Polish helpers — correctly scoped to CapySurfersScene

extension CapySurfersScene {

    private func syncAnimState() {
        guard let ctrl = playerController else { return }
        let derivedState: CapyState = {
            switch ctrl.state {
            case .running: return .running
            case .jumping: return .jumping
            case .sliding: return .sliding
            case .hitRecovery: return .hit
            }
        }()
        if derivedState == lastAnimState { return }
        let previous = lastAnimState
        lastAnimState = derivedState
        capyBody?.removeAction(forKey: "capy-anim")
        if let body = capyBody { CapyAnimator.apply(state: derivedState, to: body) }
        switch (previous, derivedState) {
        case (_, .jumping):
            CapyAudioEngine.shared.play(.jump)
        case (_, .sliding):
            CapyAudioEngine.shared.play(.slide)
        case (_, .hit):
            CapyAudioEngine.shared.play(.crash)
            runCameraShakeOnHit()
        default:
            break
        }
        if previous == .jumping && derivedState == .running {
            CapyAudioEngine.shared.play(.slide)
            runLandingSplashPuff()
        }
    }

    private func updateCapyShadow() {
        guard let capy = capy, let shadow = capyShadow else { return }
        shadow.position.x = capy.position.x
        let lift = max(0, capy.position.y - (playerY + 24))
        let shrink = max(0.35, 1.0 - lift / 90)
        shadow.setScale(shrink)
        shadow.alpha = 0.9 * shrink
    }

    private func runCameraShakeOnHit() {
        guard let cam = self.camera else { return }
        let rest = cam.position
        let shake = SKAction.sequence([
            SKAction.moveBy(x: 6, y: 4, duration: 0.04),
            SKAction.moveBy(x: -5, y: -3, duration: 0.04),
            SKAction.moveBy(x: 4, y: -3, duration: 0.04),
            SKAction.moveBy(x: -4, y: 5, duration: 0.04),
            SKAction.move(to: rest, duration: 0.04)
        ])
        cam.run(shake, withKey: "hit-shake")

        let slowmo = SKAction.sequence([
            SKAction.run { [weak self] in self?.speed = 0.32 },
            SKAction.wait(forDuration: 0.32),
            SKAction.run { [weak self] in self?.speed = 1.0 }
        ])
        self.run(slowmo, withKey: "hit-slowmo")
    }

    private func popDistanceMilestone(_ milestone: Int) {
        CapyAudioEngine.shared.play(.victory)
        capyBody.flatMap { CapyAnimator.apply(state: .celebrating, to: $0) }
        let burstPos = capy?.position ?? CGPoint(x: size.width / 2, y: size.height / 2)
        CapyEffects.makeMelonBurst(
            at: burstPos,
            parent: self,
            tint: UIColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        )
        runCameraShakeOnHit()
    }

    private func checkDistanceMilestoneIfNeeded() {
        let dist = surfersState?.distance ?? 0
        if lastDistanceMilestone == -1 {
            lastDistanceMilestone = (dist / 1000) * 1000
            return
        }
        let milestones = [1000, 5000, 10000]
        for m in milestones where dist >= m && lastDistanceMilestone < m {
            lastDistanceMilestone = m
            popDistanceMilestone(m)
            break
        }
    }

    private func runLandingSplashPuff() {
        guard let capy = capy else { return }
        let splash = SKShapeNode(ellipseOf: CGSize(width: 66, height: 14))
        splash.fillColor = paletteWater.withAlphaComponent(0.55)
        splash.strokeColor = .clear
        splash.position = CGPoint(x: capy.position.x, y: capy.position.y - 8)
        splash.zPosition = 4
        addChild(splash)
        splash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: CGSize(width: 1.6, height: 1.4), duration: 0.30),
                SKAction.fadeOut(withDuration: 0.30)
            ]),
            SKAction.removeFromParent()
        ]))
    }
}
