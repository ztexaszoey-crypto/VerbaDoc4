import SpriteKit

// MARK: - PlayerController
//
// Manages the player SKShapeNode: lane switching, jump arc, slide state, and
// the collision frame used by GameScene's AABB check.
//
// Ownership boundary:
//   PlayerController owns the player *node* (creates + adds to scene).
//   GameScene owns the *scene graph* — it never touches the node directly.
//
// Coordinate system: GameScene uses anchorPoint (0.5, 0.5).
//   x = 0 is screen centre; y = 0 is screen centre.

final class PlayerController {

    // MARK: - Lanes

    enum Lane: Int, CaseIterable {
        case left   = -1
        case center =  0
        case right  =  1
    }

    // MARK: - Node (read by GameScene for visual updates only)

    let node: SKShapeNode

    // MARK: - Lane state

    private(set) var currentLane: Lane   = .center
    private var targetLaneX:      CGFloat = 0

    /// How fast the player slides between lanes (pts per second).
    private let laneSpeed: CGFloat = 1400

    // MARK: - Jump state

    private(set) var isJumping: Bool   = false
    private var jumpPhase:       CGFloat = 0         // 0 → 1 over jumpDuration
    private let jumpDuration:    CGFloat = 0.70      // total seconds in the air
    private let jumpHeight:      CGFloat = 130       // peak height above baseY

    // MARK: - Slide state

    private(set) var isSliding: Bool   = false
    private var slidePhase:      CGFloat = 0         // 0 → 1 over slideDuration
    private let slideDuration:   CGFloat = 0.50

    // MARK: - Layout constants

    private let bodyW: CGFloat = 58
    private let bodyH: CGFloat = 74

    // MARK: - Scene ref + base Y

    private weak var scene: GameScene?
    private var baseY: CGFloat = 0

    // MARK: - Init

    init(scene: GameScene) {
        self.scene = scene
        self.baseY = scene.playerBaseY

        // Placeholder: brown rounded rect (capybara body)
        node = SKShapeNode(rectOf: CGSize(width: bodyW, height: bodyH), cornerRadius: 12)
        node.fillColor   = SKColor(red: 0.54, green: 0.36, blue: 0.18, alpha: 1.0)
        node.strokeColor = SKColor(red: 0.36, green: 0.22, blue: 0.10, alpha: 1.0)
        node.lineWidth   = 2
        node.zPosition   = 10

        let startX = scene.laneXPositions[Lane.center.rawValue] ?? 0
        node.position = CGPoint(x: startX, y: baseY)
        targetLaneX   = startX

        scene.addChild(node)
        addCapybaraDetails()
    }

    /// Minimal placeholder features: two ears + two dot eyes.
    private func addCapybaraDetails() {
        // Ears
        for xOff: CGFloat in [-18, 18] {
            let ear = SKShapeNode(ellipseOf: CGSize(width: 16, height: 12))
            ear.fillColor   = node.fillColor
            ear.strokeColor = node.strokeColor
            ear.lineWidth   = 1.5
            ear.position    = CGPoint(x: xOff, y: bodyH * 0.50 - 2)
            ear.zPosition   = 0
            node.addChild(ear)
        }
        // Eyes
        for xOff: CGFloat in [-12, 12] {
            let eye = SKShapeNode(ellipseOf: CGSize(width: 8, height: 8))
            eye.fillColor   = SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1)
            eye.strokeColor = .clear
            eye.position    = CGPoint(x: xOff, y: 14)
            eye.zPosition   = 1
            node.addChild(eye)
        }
        // Nose
        let nose = SKShapeNode(ellipseOf: CGSize(width: 14, height: 8))
        nose.fillColor   = SKColor(red: 0.70, green: 0.48, blue: 0.30, alpha: 1)
        nose.strokeColor = .clear
        nose.position    = CGPoint(x: 0, y: -4)
        nose.zPosition   = 1
        node.addChild(nose)
    }

    // MARK: - Scene resize

    func didSceneResize() {
        guard let scene else { return }
        baseY = scene.playerBaseY
        // Re-snap to current lane without animating
        let x = scene.laneXPositions[currentLane.rawValue] ?? 0
        targetLaneX     = x
        node.position.x = x
        node.position.y = baseY
    }

    // MARK: - Reset (call before each new run)

    func reset() {
        currentLane = .center
        isJumping   = false
        isSliding   = false
        jumpPhase   = 0
        slidePhase  = 0
        node.yScale = 1
        node.xScale = 1

        guard let scene else { return }
        baseY = scene.playerBaseY
        let x = scene.laneXPositions[Lane.center.rawValue] ?? 0
        targetLaneX   = x
        node.position = CGPoint(x: x, y: baseY)
    }

    // MARK: - Input

    func moveLeft() {
        guard !isSliding else { return }
        let next = currentLane.rawValue - 1
        if let lane = Lane(rawValue: next) {
            currentLane = lane
            targetLaneX = scene?.laneXPositions[lane.rawValue] ?? targetLaneX
        }
    }

    func moveRight() {
        guard !isSliding else { return }
        let next = currentLane.rawValue + 1
        if let lane = Lane(rawValue: next) {
            currentLane = lane
            targetLaneX = scene?.laneXPositions[lane.rawValue] ?? targetLaneX
        }
    }

    func jump() {
        guard !isJumping else { return }
        // Cancel slide if active
        if isSliding {
            isSliding  = false
            slidePhase = 0
            node.yScale = 1
        }
        isJumping = true
        jumpPhase = 0
    }

    func slide() {
        guard !isSliding, !isJumping else { return }
        isSliding  = true
        slidePhase = 0
    }

    // MARK: - Update (called every frame from GameScene)

    func update(dt: CGFloat) {
        updateLane(dt: dt)
        updateJump(dt: dt)
        updateSlide(dt: dt)
    }

    private func updateLane(dt: CGFloat) {
        let diff = targetLaneX - node.position.x
        guard abs(diff) > 0.5 else {
            node.position.x = targetLaneX
            return
        }
        let step = laneSpeed * dt
        if abs(diff) <= step {
            node.position.x = targetLaneX
        } else {
            node.position.x += diff > 0 ? step : -step
        }
    }

    private func updateJump(dt: CGFloat) {
        guard isJumping else { return }
        jumpPhase = min(jumpPhase + dt / jumpDuration, 1)
        // Parabolic arc via sin: peaks at phase = 0.5
        let arc = sin(.pi * jumpPhase)
        node.position.y = baseY + jumpHeight * arc
        if jumpPhase >= 1 {
            isJumping       = false
            node.position.y = baseY
        }
    }

    private func updateSlide(dt: CGFloat) {
        guard isSliding else { return }
        slidePhase = min(slidePhase + dt / slideDuration, 1)
        // Squish vertically to 50%; expand back in last 20% of slide
        let squish: CGFloat = slidePhase < 0.8 ? 0.50 : 0.50 + (slidePhase - 0.8) / 0.2 * 0.50
        node.yScale         = squish
        // Drop the node so it stays on the ground while squished
        node.position.y = baseY - bodyH * (1 - squish) * 0.5
        if slidePhase >= 1 {
            isSliding       = false
            node.yScale     = 1
            node.position.y = baseY
        }
    }

    // MARK: - Collision frame (inset 20% from visual for fairness)

    var collisionFrame: CGRect {
        let currentH = bodyH * (isSliding ? node.yScale : 1.0)
        let insetW   = bodyW   * 0.80
        let insetH   = currentH * 0.80
        return CGRect(
            x:      node.position.x - insetW  / 2,
            y:      node.position.y - insetH  / 2,
            width:  insetW,
            height: insetH
        )
    }
}
