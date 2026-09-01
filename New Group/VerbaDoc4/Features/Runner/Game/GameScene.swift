import SpriteKit

// MARK: - GameScene
//
// The SpriteKit SKScene for VerbaFlow Runner.
//
// Coordinate system:
//   anchorPoint = (0.5, 0.5) — origin at screen centre.
//   x: negative = left   y: negative = bottom
//   x: positive = right  y: positive = top
//
// Ownership contract:
//   GameScene owns: background tiles, lane lines, direct scene-graph mutations.
//   PlayerController owns: player node creation + state.
//   ObstacleManager owns: obstacle pool + spawn logic.
//
// Threading: SpriteKit calls update() on the main thread, so all
//   @MainActor callbacks (RunSessionManager) are safe to invoke here directly.

final class GameScene: SKScene {

    // MARK: - Callbacks (set by RunSessionManager before startRun)
    var onGameOver:    (() -> Void)?
    var onGateHit:     (() -> Void)?                        // gate obstacle contacted
    var onScoreUpdate: ((Int, Int, Double) -> Void)?        // score, metres, multiplier
    var onTimeUpdate:  ((TimeInterval) -> Void)?

    // MARK: - Sub-systems (initialised in didMove)
    private(set) var playerController: PlayerController!
    private(set) var obstacleManager:  ObstacleManager!

    // MARK: - Background
    private var backgroundTiles: [SKShapeNode] = []
    private var leftDivider:     SKShapeNode?
    private var rightDivider:    SKShapeNode?

    // MARK: - Game state
    private(set) var isRunning:          Bool         = false
    private(set) var distancePts:        CGFloat      = 0   // accumulated scene-units
    private      var gameSpeed:          CGFloat      = 300  // scene-units / second
    private      var score:              Int          = 0
    private      var multiplier:         Double       = 1.0
    private      var runStartTime:       TimeInterval = 0
    private      var lastUpdateTime:     TimeInterval = 0
    private      var gameOverFired:      Bool         = false

    /// Speed multiplier from VerbaFlowEngine mode (GameBridge.speedMultiplier). Set by RunSessionManager.
    var engineSpeedMultiplier:   CGFloat = 1.0
    /// Spawn interval scale from VerbaFlowEngine mode (GameBridge.spawnIntervalScale). Set by RunSessionManager.
    var engineIntervalScale:     CGFloat = 1.0

    /// When > 0, collisions are ignored (post-gate grace period to prevent instant death).
    private var invincibilityTimer: CGFloat = 0

    /// Set to true by RunSessionManager when ChallengeManager wants a gate spawned.
    var pendingGate: Bool = false

    // MARK: - Lane geometry (computed from size; read by PlayerController + ObstacleManager)
    private(set) var laneXPositions: [Int: CGFloat] = [:]  // -1, 0, 1 → x
    private(set) var playerBaseY:     CGFloat         = 0
    private(set) var spawnY:          CGFloat         = 0
    private(set) var despawnY:        CGFloat         = 0

    // MARK: - Derived
    private var laneWidth: CGFloat { size.width / 3 }

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        anchorPoint     = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.07, green: 0.16, blue: 0.14, alpha: 1)

        computeGeometry()
        buildBackground()

        playerController = PlayerController(scene: self)
        obstacleManager  = ObstacleManager(scene: self)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        computeGeometry()
        buildBackground()
        playerController?.didSceneResize()
        obstacleManager?.didSceneResize()
    }

    // MARK: - Geometry

    private func computeGeometry() {
        let lw = size.width / 3
        laneXPositions = [-1: -lw, 0: 0, 1: lw]
        playerBaseY =  -(size.height * 0.30)
        spawnY      =   (size.height * 0.50) + 150
        despawnY    =  -(size.height * 0.50) - 150
    }

    // MARK: - Background

    private func buildBackground() {
        backgroundTiles.forEach { $0.removeFromParent() }
        backgroundTiles.removeAll()
        leftDivider?.removeFromParent()
        rightDivider?.removeFromParent()

        guard size.width > 10 else { return }

        let tileH = size.height
        let tileW = size.width
        let laneW = tileW / 3

        // Three recycling tiles stacked vertically
        for i in 0..<3 {
            let tile = SKShapeNode(rectOf: CGSize(width: tileW, height: tileH))
            tile.fillColor   = SKColor(red: 0.07, green: 0.16, blue: 0.14, alpha: 1)
            tile.strokeColor = .clear
            tile.position    = CGPoint(x: 0, y: CGFloat(i - 1) * tileH)
            tile.zPosition   = -10
            addChild(tile)
            backgroundTiles.append(tile)
        }

        // Lane dividers
        let divH = size.height * 8
        for (i, xPos) in [(-laneW / 2), (laneW / 2)].enumerated() {
            let line = SKShapeNode(rectOf: CGSize(width: 2, height: divH))
            line.fillColor   = SKColor.white.withAlphaComponent(0.22)
            line.strokeColor = .clear
            line.position    = CGPoint(x: xPos, y: 0)
            line.zPosition   = -9
            addChild(line)
            if i == 0 { leftDivider  = line }
            else       { rightDivider = line }
        }
    }

    // MARK: - Run control

    func startRun() {
        isRunning             = true
        distancePts           = 0
        gameSpeed             = 300
        score                 = 0
        multiplier            = 1.0
        lastUpdateTime        = 0
        runStartTime          = 0
        gameOverFired         = false
        invincibilityTimer    = 0
        pendingGate           = false
        engineSpeedMultiplier = 1.0
        obstacleManager?.reset()
        playerController?.reset()
    }

    func stopRun() {
        isRunning = false
    }

    /// Resume after a gate question — does NOT reset any state.
    func resumeRun() {
        invincibilityTimer = 1.5   // 1.5 s grace period so frozen obstacles don't instant-kill
        isRunning          = true
    }

    func resetRun() {
        isRunning             = false
        distancePts           = 0
        gameSpeed             = 300
        score                 = 0
        multiplier            = 1.0
        lastUpdateTime        = 0
        gameOverFired         = false
        invincibilityTimer    = 0
        pendingGate           = false
        engineSpeedMultiplier = 1.0
        obstacleManager?.reset()
        playerController?.reset()
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard isRunning else { return }

        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        if runStartTime   == 0 { runStartTime   = currentTime }

        let dt = CGFloat(min(currentTime - lastUpdateTime, 1.0 / 20.0))
        lastUpdateTime = currentTime
        guard dt > 0 else { return }

        // ── Invincibility (post-gate grace period) ────────────────────────────
        if invincibilityTimer > 0 { invincibilityTimer -= dt }

        // ── Distance + speed ramp ─────────────────────────────────────────────
        // Base: +50 units/s per 1 000 pts, capped at 700 units/s.
        // Engine-mode multiplier from GameBridge applied on top.
        distancePts += gameSpeed * dt
        let baseSpeed = min(300 + (distancePts / 1_000) * 50, 700)
        gameSpeed     = min(baseSpeed * engineSpeedMultiplier, 900)

        // ── Metrics ───────────────────────────────────────────────────────────
        let metres  = Int(distancePts / 10)
        score       = Int(Double(metres) * multiplier)
        let elapsed = currentTime - runStartTime

        onScoreUpdate?(score, metres, multiplier)
        onTimeUpdate?(elapsed)

        // ── Background scroll ─────────────────────────────────────────────────
        scrollBackground(dt: dt)

        // ── Sub-system updates ────────────────────────────────────────────────
        guard let om = obstacleManager, let pc = playerController else { return }
        om.update(dt: dt, gameSpeed: gameSpeed, intervalScale: engineIntervalScale)
        pc.update(dt: dt)

        // ── Collision ─────────────────────────────────────────────────────────
        guard !gameOverFired, invincibilityTimer <= 0 else { return }
        switch checkCollisions() {
        case .none: break
        case .obstacle:
            gameOverFired = true
            stopRun()
            onGameOver?()
        case .gate:
            obstacleManager.clearGate()
            stopRun()
            onGateHit?()
        }
    }

    // MARK: - Scroll

    private func scrollBackground(dt: CGFloat) {
        let delta = gameSpeed * dt
        let tileH = size.height
        for tile in backgroundTiles {
            tile.position.y -= delta
            if tile.position.y + tileH * 0.5 < -(tileH * 0.5) {
                tile.position.y += tileH * CGFloat(backgroundTiles.count)
            }
        }
    }

    // MARK: - Collision (AABB)

    private enum CollisionResult { case none, obstacle, gate }

    private func checkCollisions() -> CollisionResult {
        let playerFrame = playerController.collisionFrame
        for obs in obstacleManager.activeObstacles {
            guard playerFrame.intersects(obs.node.frame) else { continue }
            return obs.type == .gate ? .gate : .obstacle
        }
        return .none
    }

    // MARK: - Input forwarding

    func handleSwipeLeft()  { guard isRunning else { return }; playerController?.moveLeft()  }
    func handleSwipeRight() { guard isRunning else { return }; playerController?.moveRight() }
    func handleSwipeUp()    { guard isRunning else { return }; playerController?.jump()      }
    func handleSwipeDown()  { guard isRunning else { return }; playerController?.slide()     }
}
