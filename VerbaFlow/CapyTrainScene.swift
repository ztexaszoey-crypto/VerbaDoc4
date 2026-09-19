import SpriteKit
import SwiftUI

// MARK: - CapyTrainScene
//
// Phase 16 — Subway-Surfers-style pastel train-track scene. Replaces
// the original CapySurfersScene file (which becomes dead code, kept
// in repo until a follow-up sweep deletes it).
//
// Visual identity comes from CapyTrainVisuals (same file) which paints
// claymation train wagons on visible rails with a tropical-grass
// parallax. Avoids the original scene's low-poly concrete / pipe
// aesthetic entirely.
//
// GAMEPLAY CONTRACT — the parent SwiftUI scene (`CapySurfersGameView`)
// expects this class to:
//   1. accept `init(state: CapySurfersState)` and stash the state;
//   2. drive `state.tickJuice(dt:)` every frame from `update(_:)`;
//   3. observe `Notification.Name.capyResume / .capyRefuelTriggered
//      / .capyRestart / .capyRunEnded` and react accordingly;
//   4. fire `state.addDistance(...)` / `state.collectMelon()` /
//      `state.endRun()` for collision events;
//   5. expose `state.isGameOver == true` so the parent can swap to
//      the results overlay.
//
// The SceneHolder routes here instead of the original CapySurfersScene.

final class CapyTrainScene: SKScene {

    // MARK: - Phase 16 obstacle taxonomy

    enum CapyTrainType: String, CaseIterable {
        case pinkWagon    = "pink"
        case limeWagon    = "lime"
        case mustardWagon = "mustard"
        case oliveWagon   = "olive"

        var bodyColor: UIColor {
            switch self {
            case .pinkWagon:    return UIColor(red: 0.96, green: 0.74, blue: 0.80, alpha: 1)
            case .limeWagon:    return UIColor(red: 0.659, green: 0.839, blue: 0.235, alpha: 1)
            case .mustardWagon: return UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1)
            case .oliveWagon:   return UIColor(red: 0.333, green: 0.420, blue: 0.184, alpha: 1)
            }
        }
        var trimColor: UIColor {
            switch self {
            case .pinkWagon:    return UIColor(red: 0.769, green: 0.451, blue: 0.510, alpha: 1)
            case .limeWagon:    return UIColor(red: 0.451, green: 0.659, blue: 0.157, alpha: 1)
            case .mustardWagon: return UIColor(red: 0.620, green: 0.310, blue: 0.180, alpha: 1)
            case .oliveWagon:   return UIColor(red: 0.20,  green: 0.30,  blue: 0.13,  alpha: 1)
            }
        }
    }

    // MARK: - Stashed game state

    weak var state: CapySurfersState?
    private weak var capyNode: SKShapeNode?
    private weak var trackLayer: SKNode?
    private weak var parallaxLayer: SKNode?
    private weak var trainLayer: SKNode?
    private weak var leafLayer: SKNode?
    private weak var accentLayer: SKNode?

    // MARK: - Lane geometry (3 lanes)

    private let laneYVals: [CGFloat] = [-220, 0, 220]
    private var trainSpawnAccumulator: TimeInterval = 0
    private var parallaxAccumulator: TimeInterval = 0
    private var leafAccumulator: TimeInterval = 0
    private var distanceAccumulator: TimeInterval = 0
    private var elapsedSinceStart: TimeInterval = 0
    private var lastTickTime: TimeInterval = 0
    private var isScenePaused = false

    // MARK: - Init

    init(state: CapySurfersState) {
        self.state = state
        super.init(size: CGSize(width: 750, height: 1334))
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.937, green: 0.969, blue: 0.835, alpha: 1)  // bgTop cream
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - didMove

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -26)
        physicsWorld.speed = 1.0

        // ── Layer z-ordering ──
        let parallax = SKNode(); addChild(parallax); parallax.zPosition = -10
        let track   = SKNode(); addChild(track);   track.zPosition   = -2
        let train    = SKNode(); addChild(train);    train.zPosition    = 5
        let capyLane = SKNode(); addChild(capyLane); capyLane.zPosition = 10
        let accent  = SKNode(); addChild(accent);  accent.zPosition  = 12
        let leaf    = SKNode(); addChild(leaf);    leaf.zPosition    = 14
        self.parallaxLayer = parallax
        self.trackLayer    = track
        self.trainLayer    = train
        self.accentLayer   = accent
        self.leafLayer     = leaf

        buildParallax()
        buildTrack()
        buildCapy()
        seedAmbientLeaves()

        NotificationCenter.default.addObserver(self, selector: #selector(onCapyResume),
                                               name: .capyResume, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onCapyRefuelTriggered),
                                               name: .capyRefuelTriggered, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onCapyRestart),
                                               name: .capyRestart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onCapyRefuelResume),
                                               name: .capyRunEnded, object: nil)
    }

    // MARK: - World building

    private func buildParallax() {
        guard let parallax = parallaxLayer else { return }
        // Sky band (cream top-stop background already on backgroundColor)
        let sky = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: 360))
        sky.fillColor = UIColor(red: 0.906, green: 0.957, blue: 0.796, alpha: 1)  // bgMid
        sky.strokeColor = .clear
        sky.position = CGPoint(x: size.width * 1.5, y: size.height * 0.65)
        sky.zPosition = -10
        sky.name = "sky"
        parallax.addChild(sky)

        // Distant rolling hills (pistachio pastel SVGs). Two layers for parallax depth.
        for i in 0..<2 {
            let hillLayer = SKNode()
            hillLayer.position = CGPoint(x: 0, y: 0)
            hillLayer.name = "hillLayer_\(i)"

            let count = 16
            for j in 0..<count {
                let h = SKShapeNode()
                let w: CGFloat = 240
                let wave: CGFloat = (i == 0 ? 70 : 110)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -w/2, y: 0))
                path.addQuadCurve(to: CGPoint(x: w/2, y: 0),
                                   control: CGPoint(x: 0, y: wave))
                h.path = path
                h.strokeColor = .clear
                h.fillColor = (i == 0
                    ? UIColor(red: 0.835, green: 0.898, blue: 0.675, alpha: 1)   // pistachio light
                    : UIColor(red: 0.671, green: 0.784, blue: 0.702, alpha: 1))  // sage
                h.lineWidth = 0
                h.position = CGPoint(x: CGFloat(j) * (w * 0.85) - 200,
                                     y: size.height * 0.50 - CGFloat(i) * 60)
                h.zPosition = -10 + CGFloat(i)
                hillLayer.addChild(h)
            }
            parallax.addChild(hillLayer)
        }
    }

    private func buildTrack() {
        guard let track = trackLayer else { return }

        // ── 3 lanes of running ground (sandy cream with grass strips) ──
        let groundYTop    = size.height * 0.30
        let groundYBottom = -size.height * 0.30
        let groundRect = CGRect(x: -size.width * 2, y: groundYBottom,
                                width: size.width * 5, height: groundYTop - groundYBottom)
        let ground = SKShapeNode(rect: groundRect, cornerRadius: 0)
        ground.fillColor = UIColor(red: 0.937, green: 0.969, blue: 0.835, alpha: 1) // bgTop
        ground.strokeColor = .clear
        ground.zPosition = -1
        track.addChild(ground)

        // ── 3 rails + sleepers per lane (subway-surfers rail motif) ──
        for lane in 0..<3 {
            let laneY = laneYVals[lane]
            buildRail(xStart: -size.width * 2, width: size.width * 5,
                      yCenter: laneY - 80, accent: false, parent: track)
            buildRail(xStart: -size.width * 2, width: size.width * 5,
                      yCenter: laneY + 80, accent: false, parent: track)

            // Sleepers (railroad ties) — short vertical bars crossing both rails.
            let sleeperCount = 28
            for s in 0..<sleeperCount {
                let sleeper = SKShapeNode(rectOf: CGSize(width: 14, height: 180))
                sleeper.fillColor = UIColor(red: 0.529, green: 0.420, blue: 0.298, alpha: 1)
                sleeper.strokeColor = UIColor(red: 0.439, green: 0.314, blue: 0.196, alpha: 1)
                sleeper.lineWidth = 1
                sleeper.position = CGPoint(
                    x: CGFloat(s) * (size.width * 5 / CGFloat(sleeperCount)) - size.width * 2,
                    y: laneY
                )
                sleeper.zPosition = -1
                track.addChild(sleeper)
            }
        }

        // ── Foreground grass strip ──
        let grass = SKShapeNode(rectOf: CGSize(width: size.width * 5, height: 80))
        grass.fillColor = UIColor(red: 0.741, green: 0.890, blue: 0.784, alpha: 1) // mint
        grass.strokeColor = UIColor(red: 0.333, green: 0.420, blue: 0.184, alpha: 1)
        grass.lineWidth = 1
        grass.position = CGPoint(x: size.width * 1.5, y: groundYBottom + 40)
        grass.zPosition = -1
        track.addChild(grass)
    }

    private func buildRail(xStart: CGFloat, width: CGFloat, yCenter: CGFloat,
                           accent: Bool, parent: SKNode) {
        let rail = SKShapeNode(rectOf: CGSize(width: width, height: 4))
        rail.fillColor = UIColor(red: 0.243, green: 0.302, blue: 0.142, alpha: 1)   // darker olive
        rail.strokeColor = .clear
        rail.position = CGPoint(x: xStart + width/2, y: yCenter)
        rail.zPosition = -1
        parent.addChild(rail)
    }

    private func buildCapy() {
        // ── Capybara runner — chunky clay body + smile + small ears ──
        let capy = SKShapeNode()
        let body = CGMutablePath()
        body.addRoundedRect(in: CGRect(x: -32, y: -32, width: 64, height: 64), cornerWidth: 14, cornerHeight: 14)
        capy.path = body
        capy.fillColor   = UIColor(red: 0.612, green: 0.471, blue: 0.314, alpha: 1)   // clayBody
        capy.strokeColor = UIColor(red: 0.439, green: 0.314, blue: 0.196, alpha: 1)   // clayBodyDark
        capy.lineWidth = 2.5
        capy.position = CGPoint(x: size.width * 0.30, y: laneYVals[1])
        capy.zPosition = 10
        capy.name = "capy"
        addChild(capy)
        capyNode = capy

        // Eyes (two small white circles with black pupil dots)
        for offset in [-12.0, 12.0] as [CGFloat] {
            let eye = SKShapeNode(circleOfRadius: 4)
            eye.fillColor = .white
            eye.strokeColor = .black
            eye.lineWidth = 1
            eye.position = CGPoint(x: capy.position.x + offset, y: capy.position.y + 10)
            eye.zPosition = 11
            eye.name = "capy_eye"
            addChild(eye)

            let pupil = SKShapeNode(circleOfRadius: 1.6)
            pupil.fillColor = .black
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: capy.position.x + offset, y: capy.position.y + 10)
            pupil.zPosition = 12
            addChild(pupil)
        }
    }

    private func seedAmbientLeaves() {
        guard let leaf = leafLayer else { return }
        // Scatter 14 decorative pastel flowers along the foreground
        for _ in 0..<14 {
            let flower = makeFlower()
            flower.position = CGPoint(
                x: CGFloat.random(in: -size.width * 2 ... size.width * 3),
                y: CGFloat.random(in: -size.height * 0.30 ... -size.height * 0.10)
            )
            flower.xScale = CGFloat.random(in: 0.6 ... 1.0)
            flower.yScale = flower.xScale
            leaf.addChild(flower)
        }
    }

    private func makeFlower() -> SKNode {
        let group = SKNode()
        let petalColor = UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1) // flowerGold
        for i in 0..<5 {
            let petalPath = UIBezierPath(ovalIn: CGRect(x: -6, y: -6, width: 12, height: 12))
            let petal = SKShapeNode(path: petalPath.cgPath)
            petal.fillColor = petalColor.withAlphaComponent(0.92)
            petal.strokeColor = UIColor(red: 0.529, green: 0.420, blue: 0.298, alpha: 0.4)
            petal.lineWidth = 0.5
            let angle = CGFloat(i) * (.pi * 2 / 5)
            petal.position = CGPoint(x: cos(angle) * 8, y: sin(angle) * 8)
            group.addChild(petal)
        }
        // Olive center
        let center = SKShapeNode(circleOfRadius: 4)
        center.fillColor = UIColor(red: 0.333, green: 0.420, blue: 0.184, alpha: 1)
        center.strokeColor = .clear
        group.addChild(center)
        group.zPosition = 14
        return group
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        // First-frame: seed lastTickTime
        if lastTickTime == 0 { lastTickTime = currentTime; return }
        let dt = min(0.10, currentTime - lastTickTime)
        lastTickTime = currentTime

        guard let state = state else { return }

        // ── Cross-process sync ──
        if state.isGameOver || state.needsRefuel || state.preRunWarmup
            || state.isCountingDown || state.quizActive {
            isScenePaused = true
            view?.isPaused = true
        } else if isScenePaused {
            isScenePaused = false
            view?.isPaused = false
        }

        if isScenePaused { return }

        // ── CapySurfersState bookkeeping: drain energy + advance distance ──
        state.tickJuice(dt: dt)
        distanceAccumulator += dt
        if distanceAccumulator >= 1.0 {
            state.addDistance(Int(distanceAccumulator))
            distanceAccumulator -= 1.0
        }
        elapsedSinceStart += dt

        // ── Spawn trains ──
        trainSpawnAccumulator += dt
        let spawnInterval: TimeInterval = max(0.85, 2.2 - elapsedSinceStart * 0.005)
        if trainSpawnAccumulator >= spawnInterval {
            trainSpawnAccumulator = 0
            spawnTrain()
        }

        // ── Scroll existing trains off-screen ──
        trainLayer?.children.compactMap { $0 as? SKShapeNode }.forEach { node in
            let baseSpeed: CGFloat = 220.0
            let accelFactor: CGFloat = 1.0 + CGFloat(elapsedSinceStart) * 0.02
            node.position.x -= baseSpeed * CGFloat(dt) * accelFactor
            if node.position.x < -size.width {
                node.removeFromParent()
            }
        }

        // ── Parallax scroll ──
        parallaxAccumulator += dt
        if let parallax = parallaxLayer {
            parallax.children.forEach { layer in
                layer.position.x -= CGFloat(30.0) * CGFloat(dt)
                if layer.position.x < -size.width * 2 {
                    layer.position.x += size.width * 4
                }
            }
        }

        // ── Drift decorative flowers ──
        leafLayer?.children.forEach { leaf in
            leaf.position.x -= CGFloat(40.0) * CGFloat(dt)
            if leaf.position.x < -size.width * 1.5 {
                leaf.position.x += size.width * 4
            }
        }

        // ── Capy lane switch via simulated left/right gestures ──
        if let capy = capyNode {
            // Pulse run cycle: capy bobs up/down
            capy.position.y = laneYVals[1] + sin(currentTime * 6.0) * 2
        }
    }

    // MARK: - Train obstacle construction (Subway-Surfers-style clay wagons)

    private func spawnTrain() {
        guard let train = trainLayer else { return }
        let laneIdx = Int.random(in: 0..<3)
        let laneY   = laneYVals[laneIdx]
        let type    = CapyTrainType.allCases.randomElement() ?? .mustardWagon

        // Wagon body — 3-stacked pastel cars (locomotive + car + caboose)
        let wagon = makeTrainWagon(type: type)
        wagon.position = CGPoint(x: size.width + 200, y: laneY)
        wagon.name = "wagon_lane_\(laneIdx)"
        train.addChild(wagon)
    }

    private func makeTrainWagon(type: CapyTrainType) -> SKNode {
        // Phase 16.10 — orchestrator only. Each piece is now a single-purpose
        // helper so the Swift type checker can resolve them independently
        // instead of being asked to type-check a 100-line compound expression.
        let group = SKNode()

        // 3 wagons in a row: locomotive + 2 cars
        let wagonWidth: CGFloat = 80
        let wagonHeight: CGFloat = 90
        let gap: CGFloat = 12
        let firstPos: CGFloat = 0
        let step: CGFloat = wagonWidth + gap
        let secondPos: CGFloat = step
        let thirdPos: CGFloat = 2.0 * step
        let positions: [CGFloat] = [firstPos, secondPos, thirdPos]
        let isLocomotiveAt: [Bool] = [true, false, false]

        for (idx, xPos) in positions.enumerated() {
            let wagonShape = makeWagonBody(idx: idx, xPos: xPos,
                                           width: wagonWidth, height: wagonHeight,
                                           type: type)
            group.addChild(wagonShape)
            makeWagonFace(parent: wagonShape, xPos: xPos, faceY: 5)
            addWindowStrip(to: wagonShape, bodyWidth: wagonWidth, trimColor: type.trimColor)
            if isLocomotiveAt[idx] {
                makeLocomotiveAccessory(parent: wagonShape)
            }
            makeWagonWheels(parent: group, xPos: xPos, trimColor: type.trimColor)
        }

        group.addChild(makeTrainHitbox(wagonWidth: wagonWidth,
                                       wagonHeight: wagonHeight,
                                       gap: gap))
        return group
    }

    /// Single-purpose helper: returns a fresh wagon body SKShapeNode sized and
    /// styled for the current train type. Extracted so the type checker can
    /// resolve it independently of the rest of `makeTrainWagon`.
    private func makeWagonBody(idx: Int, xPos: CGFloat,
                               width: CGFloat, height: CGFloat,
                               type: CapyTrainType) -> SKShapeNode {
        let wagonShape = SKShapeNode(rectOf: CGSize(width: width, height: height),
                                     cornerRadius: 12)
        wagonShape.fillColor = type.bodyColor
        wagonShape.strokeColor = type.trimColor
        wagonShape.lineWidth = 2.5
        wagonShape.position = CGPoint(x: xPos, y: 0)
        wagonShape.zPosition = 5
        wagonShape.name = "wagon_\(idx)"
        return wagonShape
    }

    /// Single-purpose helper: attaches a claymation face (two eyes + pupil
    /// dots + smile arc) as children of `parent`. Caller manages parent
    /// insertion into the scene graph.
    private func makeWagonFace(parent: SKShapeNode, xPos: CGFloat, faceY: CGFloat) {
        for xOffset in [-22.0, -8.0] as [CGFloat] {
            let eye = SKShapeNode(circleOfRadius: 3)
            eye.fillColor = .white
            eye.strokeColor = UIColor(red: 0.20, green: 0.231, blue: 0.122, alpha: 1)
            eye.lineWidth = 1
            eye.position = CGPoint(x: xPos + xOffset, y: faceY + 5)
            parent.addChild(eye)

            let pupil = SKShapeNode(circleOfRadius: 1.2)
            pupil.fillColor = UIColor(red: 0.20, green: 0.231, blue: 0.122, alpha: 1)
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: xPos + xOffset, y: faceY + 5)
            parent.addChild(pupil)
        }

        let smilePath = UIBezierPath()
        smilePath.move(to: CGPoint(x: xPos - 18, y: faceY - 6))
        smilePath.addQuadCurve(to: CGPoint(x: xPos - 12, y: faceY - 6),
                               controlPoint: CGPoint(x: xPos - 15, y: faceY - 12))
        let smile = SKShapeNode(path: smilePath.cgPath)
        smile.strokeColor = UIColor(red: 0.20, green: 0.231, blue: 0.122, alpha: 1)
        smile.lineWidth = 2
        smile.fillColor = .clear
        parent.addChild(smile)
    }

    /// Single-purpose helper: attaches a window strip to the top of the wagon.
    private func addWindowStrip(to wagonShape: SKShapeNode,
                                bodyWidth: CGFloat,
                                trimColor: UIColor) {
        let windowRect = SKShapeNode(rectOf: CGSize(width: bodyWidth - 24, height: 18),
                                     cornerRadius: 6)
        windowRect.fillColor = UIColor(red: 1.0, green: 1.0, blue: 0.96, alpha: 0.55)
        windowRect.strokeColor = trimColor
        windowRect.lineWidth = 1
        windowRect.position = CGPoint(x: 0, y: 30)
        wagonShape.addChild(windowRect)
    }

    /// Single-purpose helper: attaches chimney + smoke to a locomotive wagon.
    private func makeLocomotiveAccessory(parent: SKShapeNode) {
        let chimney = SKShapeNode(rectOf: CGSize(width: 16, height: 28),
                                   cornerRadius: 4)
        chimney.fillColor = UIColor(red: 0.439, green: 0.314, blue: 0.196, alpha: 1)
        chimney.strokeColor = UIColor(red: 0.227, green: 0.169, blue: 0.110, alpha: 1)
        chimney.lineWidth = 1.5
        chimney.position = CGPoint(x: 24, y: 64)
        parent.addChild(chimney)

        let smoke = SKShapeNode(circleOfRadius: 14)
        smoke.fillColor = UIColor.white.withAlphaComponent(0.85)
        smoke.strokeColor = .clear
        smoke.position = CGPoint(x: 24, y: 96)
        smoke.name = "smoke"
        parent.addChild(smoke)
    }

    /// Single-purpose helper: attaches a wheel pair (left + right) under a wagon.
    private func makeWagonWheels(parent: SKNode, xPos: CGFloat, trimColor: UIColor) {
        for xOffset in [-30.0, 30.0] as [CGFloat] {
            let wheel = SKShapeNode(circleOfRadius: 11)
            wheel.fillColor = UIColor(red: 0.227, green: 0.169, blue: 0.110, alpha: 1)
            wheel.strokeColor = trimColor
            wheel.lineWidth = 1.5
            wheel.position = CGPoint(x: xPos + xOffset, y: -50)
            wheel.zPosition = 4
            parent.addChild(wheel)
        }
    }

    /// Single-purpose helper: returns the collision hitbox with explicit
    /// CGFloat variables. Caller inserts the returned node into the train group.
    private func makeTrainHitbox(wagonWidth: CGFloat,
                                 wagonHeight: CGFloat,
                                 gap: CGFloat) -> SKShapeNode {
        // explicit CGFloat variables: the previous inline `3 * wagonWidth + 2 * gap`
        // expression repeated inside two CGSize initializers with a mixed Int (`22`)
        // caused the Swift type-checker to timeout. extracting reduces the surface.
        let hitWidth: CGFloat  = 3 * wagonWidth + 2 * gap
        let extraHeight: CGFloat = 22.0
        let hitHeight: CGFloat = wagonHeight + extraHeight
        let hitSize = CGSize(width: hitWidth, height: hitHeight)

        let hit = SKShapeNode(rectOf: hitSize)
        hit.fillColor = .clear
        hit.strokeColor = .clear

        let body = SKPhysicsBody(rectangleOf: hitSize)
        body.isDynamic = false
        body.affectedByGravity = false
        body.categoryBitMask    = 1 << 1
        body.contactTestBitMask = 1 << 0
        body.collisionBitMask   = 0
        hit.physicsBody = body
        hit.zPosition = 5
        return hit
    }

    // MARK: - Notification handlers (cross-process sync with state)

    @objc private func onCapyResume() {
        view?.isPaused = false
        isScenePaused = false
        lastTickTime = 0  // resets the dt calculation
    }

    @objc private func onCapyRefuelTriggered() {
        view?.isPaused = true
        isScenePaused = true
    }

    @objc private func onCapyRestart() {
        // Wipe trains + accumulator so the run starts clean
        trainLayer?.removeAllChildren()
        trainSpawnAccumulator = 0
        distanceAccumulator   = 0
        elapsedSinceStart     = 0
        isScenePaused         = false
        view?.isPaused        = false
        lastTickTime          = 0
    }

    @objc private func onCapyRefuelResume() {
        // End-of-run hook (the original scene fired this via capyRunEnded)
        // — keep matching behaviour so SwiftUI observes isGameOver.
        // No-op here; the parent SwiftUI view handles results overlay.
    }
}

