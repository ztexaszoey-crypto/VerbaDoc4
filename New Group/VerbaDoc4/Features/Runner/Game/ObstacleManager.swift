import SpriteKit

// MARK: - ObstacleManager
//
// Pre-allocates a fixed pool of SKShapeNodes and recycles them as obstacles
// scroll off the bottom of the screen.  No SKNode allocation occurs during
// gameplay — only position + visibility changes.
//
// Obstacle types (Sprint 2+):
//   .regular — dodge by changing lane (red, standard width)
//   .gate    — answer a question to clear (white, full screen width)
//
// Difficulty scaling:
//   Spawn interval shrinks from 2.0s → 0.65s as distance grows.
//   GameBridge.spawnIntervalScale() applies an engine-mode multiplier on top.
//
// Threading: all methods called from GameScene.update() on the main thread.

final class ObstacleManager {

    // MARK: - Obstacle type

    enum ObstacleType {
        case regular   // dodge by lane change
        case gate      // answer a question; does not cause game over on collision
    }

    // MARK: - Active obstacle record

    struct ActiveObstacle {
        let node: SKShapeNode
        let lane: PlayerController.Lane
        let type: ObstacleType
    }

    // MARK: - Pool

    private var pool:           [SKShapeNode]      = []
    private let poolSize:       Int                = 20
    private(set) var activeObstacles: [ActiveObstacle] = []

    // MARK: - Spawn state

    private var spawnTimer:          CGFloat = 0
    private var nextSpawnInterval:   CGFloat = 2.0   // seconds until next spawn
    private let minSpawnInterval:    CGFloat = 0.65
    private var spawnIntervalScale:  CGFloat = 1.0   // set by GameBridge each update

    /// Tracks the last lane used so we never place two obstacles in the same lane
    /// back-to-back — avoids unwinnable "two in a row" patterns.
    private var lastSpawnedLane: PlayerController.Lane? = nil

    // MARK: - Obstacle dimensions
    // Logs are wider and flatter than the old rectangle — more like a fallen tree trunk.

    private let obstacleW: CGFloat = 96
    private let obstacleH: CGFloat = 38

    // MARK: - Scene ref

    private weak var scene: GameScene?

    // MARK: - Init

    init(scene: GameScene) {
        self.scene = scene
        buildPool(scene: scene)
    }

    private func buildPool(scene: SKScene) {
        for _ in 0..<poolSize {
            let node = makeRegularNode()
            node.isHidden  = true
            node.position  = CGPoint(x: 0, y: -99_999)
            scene.addChild(node)
            pool.append(node)
        }
    }

    private func makeRegularNode() -> SKShapeNode {
        // Pill-shaped log — high corner radius gives rounded-trunk silhouette
        let node = SKShapeNode(
            rectOf: CGSize(width: obstacleW, height: obstacleH),
            cornerRadius: obstacleH / 2
        )
        applyRegularAppearance(node)
        node.zPosition = 5
        addLogDetail(to: node)
        return node
    }

    /// Adds bark-grain lines and end-cap shading to make the shape read as a log.
    private func addLogDetail(to node: SKShapeNode) {
        // Darker inner shadow on the top face (simulates rounded log volume)
        let highlight = SKShapeNode(
            rectOf: CGSize(width: obstacleW - 20, height: obstacleH * 0.35),
            cornerRadius: 4
        )
        highlight.fillColor   = SKColor(white: 1.0, alpha: 0.08)
        highlight.strokeColor = .clear
        highlight.position    = CGPoint(x: 0, y: obstacleH * 0.18)
        highlight.zPosition   = 1
        node.addChild(highlight)

        // Two bark-grain lines
        for yOff: CGFloat in [-4, 4] {
            let grain = SKShapeNode(
                rectOf: CGSize(width: obstacleW * 0.55, height: 1.5),
                cornerRadius: 0.75
            )
            grain.fillColor   = SKColor(white: 0.0, alpha: 0.18)
            grain.strokeColor = .clear
            grain.position    = CGPoint(x: 0, y: yOff)
            grain.zPosition   = 1
            node.addChild(grain)
        }

        // End-cap circles (cut cross-section look)
        for xOff: CGFloat in [-(obstacleW / 2) + obstacleH * 0.45,
                                (obstacleW / 2) - obstacleH * 0.45] {
            let cap = SKShapeNode(ellipseOf: CGSize(width: obstacleH * 0.70,
                                                     height: obstacleH * 0.70))
            cap.fillColor   = SKColor(red: 0.20, green: 0.11, blue: 0.04, alpha: 0.55)
            cap.strokeColor = SKColor(red: 0.45, green: 0.28, blue: 0.10, alpha: 0.40)
            cap.lineWidth   = 1.0
            cap.position    = CGPoint(x: xOff, y: 0)
            cap.zPosition   = 2
            node.addChild(cap)
        }
    }

    private func applyRegularAppearance(_ node: SKShapeNode) {
        // Natural fallen-log colours: medium warm wood brown
        node.fillColor   = SKColor(red: 0.38, green: 0.22, blue: 0.08, alpha: 1)
        node.strokeColor = SKColor(red: 0.55, green: 0.35, blue: 0.14, alpha: 1)
        node.lineWidth   = 2.0
        node.xScale      = 1.0
        node.yScale      = 1.0
    }

    private func applyGateAppearance(_ node: SKShapeNode, sceneWidth: CGFloat) {
        // Reed/bamboo barrier — spans the full width, deep marsh green
        let gateW = sceneWidth - 24
        node.xScale      = gateW / obstacleW
        node.yScale      = 1.4          // slightly taller so it reads as a barrier
        node.fillColor   = SKColor(red: 0.08, green: 0.28, blue: 0.14, alpha: 0.90)
        node.strokeColor = SKColor(red: 0.28, green: 0.72, blue: 0.42, alpha: 1.00)
        node.lineWidth   = 2.0
    }

    // MARK: - Scene resize

    func didSceneResize() {
        // Obstacle positions update naturally via movement — nothing to re-layout here.
    }

    // MARK: - Reset

    func reset() {
        for obstacle in activeObstacles {
            returnToPool(obstacle.node)
        }
        activeObstacles.removeAll()
        spawnTimer         = 0
        nextSpawnInterval  = 2.0
        spawnIntervalScale = 1.0
        lastSpawnedLane    = nil
    }

    // MARK: - Update (called from GameScene.update every frame)

    func update(dt: CGFloat, gameSpeed: CGFloat, intervalScale: CGFloat) {
        guard let scene else { return }
        spawnIntervalScale = intervalScale
        moveAndRecycle(speed: gameSpeed, dt: dt, despawnY: scene.despawnY)
        tickSpawnTimer(dt: dt, scene: scene)
    }

    // MARK: - Gate management

    /// Return any active gate obstacles to the pool without triggering game over.
    func clearGate() {
        var toRemove: [Int] = []
        for (i, obs) in activeObstacles.enumerated() where obs.type == .gate {
            returnToPool(obs.node)
            toRemove.append(i)
        }
        for i in toRemove.reversed() { activeObstacles.remove(at: i) }
    }

    // MARK: - Private: movement

    private func moveAndRecycle(speed: CGFloat, dt: CGFloat, despawnY: CGFloat) {
        var expired: [Int] = []
        for (i, obs) in activeObstacles.enumerated() {
            obs.node.position.y -= speed * dt
            if obs.node.position.y < despawnY {
                expired.append(i)
            }
        }
        for i in expired.reversed() {
            returnToPool(activeObstacles[i].node)
            activeObstacles.remove(at: i)
        }
    }

    // MARK: - Private: spawn timing

    private func tickSpawnTimer(dt: CGFloat, scene: GameScene) {
        spawnTimer += dt

        // Tighten base interval as distance grows (reaches minimum by ~7 500 pts)
        let progress = min(scene.distancePts / 7_500, 1.0)
        let baseInterval = 2.0 - CGFloat(progress) * (2.0 - minSpawnInterval)
        nextSpawnInterval = max(baseInterval * spawnIntervalScale, minSpawnInterval)

        if spawnTimer >= nextSpawnInterval {
            spawnTimer = 0
            spawnNext(scene: scene)
        }
    }

    private func spawnNext(scene: GameScene) {
        guard let node = dequeue() else { return }

        if scene.pendingGate {
            spawnGate(node: node, scene: scene)
            scene.pendingGate = false
        } else {
            spawnRegular(node: node, scene: scene)
        }
    }

    private func spawnRegular(node: SKShapeNode, scene: GameScene) {
        // Exclude previous lane — guarantees the player always has a dodge option.
        let candidates = PlayerController.Lane.allCases.filter { $0 != lastSpawnedLane }
        let lane = candidates.randomElement() ?? .center
        lastSpawnedLane = lane

        applyRegularAppearance(node)
        node.position = CGPoint(x: scene.laneXPositions[lane.rawValue] ?? 0, y: scene.spawnY)
        node.isHidden = false
        activeObstacles.append(ActiveObstacle(node: node, lane: lane, type: .regular))
    }

    private func spawnGate(node: SKShapeNode, scene: GameScene) {
        applyGateAppearance(node, sceneWidth: scene.size.width)
        node.position = CGPoint(x: 0, y: scene.spawnY)   // center of all three lanes
        node.isHidden = false
        activeObstacles.append(ActiveObstacle(node: node, lane: .center, type: .gate))
    }

    // MARK: - Pool helpers

    private func dequeue() -> SKShapeNode? {
        pool.first(where: { $0.isHidden })
    }

    private func returnToPool(_ node: SKShapeNode) {
        node.isHidden   = true
        node.position.y = -99_999
        // Restore regular appearance so the node is clean for the next use
        applyRegularAppearance(node)
        // Reset scale in case it was used as a gate (gate applies yScale > 1)
        node.yScale = 1.0
    }
}
