import SpriteKit
import SwiftUI

// MARK: - VerbaFlowScene
// SpriteKit infinite runner. Three lanes, obstacles, coins, barrier triggers.
// The scene pauses and calls state.presentQuestion() when a barrier is hit.
// SwiftUI overlays the question; on answer, a notification resumes the scene.

final class VerbaFlowScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Config

    private let laneXPositions: [CGFloat] = [-110, 0, 110]
    private var currentLane = 1      // 0=left, 1=center, 2=right
    private var isOnGround  = true
    private var gameSpeed:  CGFloat = 350
    private var spawnTimer: TimeInterval = 0
    private var barrierTimer: TimeInterval = 0
    private var barrierInterval: TimeInterval = 7.0   // 5-10s, randomised
    private var scoreTimer: TimeInterval = 0
    private var isPaused_   = false

    // MARK: - Nodes

    private var capybara: SKNode!
    private var capyBody:  SKShapeNode!
    private var capyEye:   SKShapeNode!
    private var groundNode: SKNode!
    private var bgLayers: [SKNode] = []
    private var scoreLabel: SKLabelNode!

    // MARK: - References

    weak var state: VerbaFlowState?
    var document: Document?
    private var questions: [FlowQuestion] = []
    private var questionIndex = 0

    // MARK: - Physics categories

    private let catCapybara: UInt32  = 0x1 << 0
    private let catObstacle: UInt32  = 0x1 << 1
    private let catGround:   UInt32  = 0x1 << 2
    private let catBarrier:  UInt32  = 0x1 << 3
    private let catCoin:     UInt32  = 0x1 << 4

    // MARK: - Init

    convenience init(state: VerbaFlowState, document: Document?) {
        self.init()
        self.state = state
        self.document = document
        self.backgroundColor = SKColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1)
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        buildQuestions()
        setupPhysics()
        setupBackground()
        setupGround()
        setupCapybara()
        setupSwipeGestures(view: view)
        setupNotifications()
        barrierInterval = Double.random(in: 5...10)
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
    }

    // MARK: - Setup

    private func buildQuestions() {
        if let doc = document, !doc.studyItems.isEmpty {
            questions = doc.studyItems.shuffled().map { item in
                let others = doc.studyItems.filter { $0.id != item.id }.shuffled().prefix(3).map(\.answer)
                var opts   = Array(others) + [item.answer]
                opts.shuffle()
                let ci = opts.firstIndex(of: item.answer) ?? 0
                let isMCQ = Bool.random() || opts.count < 4
                return FlowQuestion(question: item.question, options: opts, correctIndex: ci, topic: item.topic, isMCQ: isMCQ)
            }
        } else {
            questions = DemoFlowQuestions.all.shuffled()
        }
    }

    private func setupPhysics() {
        physicsWorld.gravity = CGVector(dx: 0, dy: -18)
        physicsWorld.contactDelegate = self
    }

    private func setupBackground() {
        // Three scrolling stripe layers for parallax effect
        let colors: [SKColor] = [
            SKColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1),
            SKColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1),
            SKColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1),
        ]
        let speeds: [CGFloat] = [60, 100, 140]

        for (i, color) in colors.enumerated() {
            let node = SKNode()
            for j in 0..<3 {
                let stripe = SKSpriteNode(color: color, size: CGSize(width: size.width + 10, height: size.height))
                stripe.position = CGPoint(x: CGFloat(j) * size.width, y: size.height / 2)
                stripe.name = "bgLayer\(i)"
                node.addChild(stripe)
            }
            node.userData = NSMutableDictionary()
            node.userData?["speed"] = speeds[i]
            addChild(node)
            bgLayers.append(node)
        }

        // Ground stripes (track lines)
        for k in 0..<20 {
            let line = SKSpriteNode(color: SKColor.white.withAlphaComponent(0.04), size: CGSize(width: 2, height: size.height * 0.4))
            line.position = CGPoint(x: CGFloat(k) * (size.width / 10), y: size.height * 0.30)
            line.name = "trackLine"
            addChild(line)
        }
    }

    private func setupGround() {
        groundNode = SKNode()
        groundNode.position = CGPoint(x: size.width / 2, y: size.height * 0.18)

        let body = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 3, height: 20))
        body.isDynamic   = false
        body.categoryBitMask    = catGround
        body.collisionBitMask   = catCapybara
        body.contactTestBitMask = catCapybara
        groundNode.physicsBody  = body
        addChild(groundNode)

        // Visual ground line
        let line = SKSpriteNode(color: SKColor(red: 0.18, green: 0.72, blue: 0.49, alpha: 0.3), size: CGSize(width: size.width, height: 2))
        line.position = CGPoint(x: size.width / 2, y: size.height * 0.18 + 10)
        addChild(line)
    }

    private func setupCapybara() {
        capybara = SKNode()
        capybara.position = CGPoint(x: size.width / 2 + laneXPositions[currentLane], y: size.height * 0.18 + 45)

        // Body
        capyBody = SKShapeNode(rectOf: CGSize(width: 52, height: 36), cornerRadius: 14)
        capyBody.fillColor   = SKColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1)
        capyBody.strokeColor = SKColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 1)
        capyBody.lineWidth   = 2
        capybara.addChild(capyBody)

        // Head bump
        let head = SKShapeNode(rectOf: CGSize(width: 28, height: 22), cornerRadius: 8)
        head.fillColor   = SKColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1)
        head.strokeColor = SKColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 1)
        head.lineWidth   = 2
        head.position    = CGPoint(x: 18, y: 16)
        capybara.addChild(head)

        // Eye
        capyEye = SKShapeNode(circleOfRadius: 4)
        capyEye.fillColor   = SKColor.black
        capyEye.strokeColor = SKColor.white
        capyEye.lineWidth   = 1
        capyEye.position    = CGPoint(x: 28, y: 18)
        capybara.addChild(capyEye)

        // Nose
        let nose = SKShapeNode(rectOf: CGSize(width: 10, height: 6), cornerRadius: 3)
        nose.fillColor = SKColor(red: 0.80, green: 0.55, blue: 0.40, alpha: 1)
        nose.position  = CGPoint(x: 32, y: 10)
        capybara.addChild(nose)

        // Physics
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 48, height: 32))
        body.allowsRotation     = false
        body.categoryBitMask    = catCapybara
        body.collisionBitMask   = catGround | catObstacle
        body.contactTestBitMask = catObstacle | catBarrier | catCoin
        capybara.physicsBody    = body

        addChild(capybara)

        // Run bob animation
        let bobUp   = SKAction.moveBy(x: 0, y: 4, duration: 0.25)
        let bobDown = SKAction.moveBy(x: 0, y: -4, duration: 0.25)
        capyBody.run(SKAction.repeatForever(SKAction.sequence([bobUp, bobDown])))
    }

    private func setupSwipeGestures(view: SKView) {
        let directions: [UISwipeGestureRecognizer.Direction] = [.left, .right, .up]
        for dir in directions {
            let g = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            g.direction = dir
            view.addGestureRecognizer(g)
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onAnswered(_:)), name: .verbaFlowAnswered, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onRestart),      name: .verbaFlowRestart,  object: nil)
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !isPaused_ else { return }

        let dt: TimeInterval = 0.016

        // Scroll track lines
        enumerateChildNodes(withName: "trackLine") { node, _ in
            node.position.x -= self.gameSpeed * 0.016
            if node.position.x < -20 {
                node.position.x += self.size.width + 40
            }
        }

        // Score over time
        scoreTimer += dt
        if scoreTimer >= 0.1 {
            scoreTimer = 0
            state?.addScore(1)
        }

        // Spawn obstacles + coins
        spawnTimer += dt
        if spawnTimer >= Double.random(in: 1.8...3.2) {
            spawnTimer = 0
            spawnObstacle()
        }

        // Barrier timer
        barrierTimer += dt
        if barrierTimer >= barrierInterval {
            barrierTimer = 0
            barrierInterval = Double.random(in: 5...10)
            spawnBarrier()
        }

        // Ramp speed
        gameSpeed = min(600, 350 + CGFloat(state?.score ?? 0) * 0.15)
    }

    // MARK: - Spawning

    private func spawnObstacle() {
        let lane     = Int.random(in: 0...2)
        let xPos     = size.width / 2 + laneXPositions[lane]
        let isDouble = Bool.random() && (state?.score ?? 0) > 200

        let obstacle = makeObstacle(at: xPos)
        addChild(obstacle)

        if isDouble {
            let gap  = Int.random(in: 0...2)
            let lane2 = (lane + gap) % 3
            if lane2 != lane {
                let o2 = makeObstacle(at: size.width / 2 + laneXPositions[lane2])
                addChild(o2)
            }
        }
    }

    private func makeObstacle(at x: CGFloat) -> SKNode {
        let h    = CGFloat.random(in: 30...55)
        let node = SKNode()
        node.position = CGPoint(x: x + size.width, y: size.height * 0.18 + h / 2 + 10)
        node.name = "obstacle"

        let shape = SKShapeNode(rectOf: CGSize(width: 32, height: h), cornerRadius: 6)
        shape.fillColor   = SKColor(red: 0.92, green: 0.32, blue: 0.32, alpha: 1)
        shape.strokeColor = SKColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1)
        shape.lineWidth   = 2
        node.addChild(shape)

        // Exclamation mark
        let label = SKLabelNode(text: "!")
        label.fontSize   = 18
        label.fontName   = "SF-Pro-Rounded-Bold"
        label.fontColor  = .white
        label.position   = CGPoint(x: 0, y: -8)
        node.addChild(label)

        let body = SKPhysicsBody(rectangleOf: CGSize(width: 28, height: h))
        body.isDynamic          = false
        body.categoryBitMask    = catObstacle
        body.contactTestBitMask = catCapybara
        node.physicsBody        = body

        let move   = SKAction.moveBy(x: -(size.width * 2.4), y: 0, duration: Double(size.width * 2.4 / gameSpeed))
        let remove = SKAction.removeFromParent()
        node.run(SKAction.sequence([move, remove]))

        return node
    }

    private func spawnBarrier() {
        let node = SKNode()
        node.position = CGPoint(x: size.width * 1.4, y: size.height / 2)
        node.name = "barrier"

        // Full-width warning panel
        let bg = SKSpriteNode(color: SKColor(red: 0.97, green: 0.58, blue: 0.18, alpha: 0.20), size: CGSize(width: 20, height: size.height))
        node.addChild(bg)

        // Barrier stripes
        for i in 0..<8 {
            let stripe = SKSpriteNode(color: SKColor(red: 0.97, green: 0.58, blue: 0.18, alpha: 0.7), size: CGSize(width: 20, height: 40))
            stripe.position = CGPoint(x: 0, y: CGFloat(i) * 50 - 170)
            node.addChild(stripe)
        }

        // Warning X mark drawn with shapes
        let xBar1 = SKShapeNode(rectOf: CGSize(width: 6, height: 28), cornerRadius: 3)
        xBar1.fillColor = SKColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
        xBar1.strokeColor = .clear; xBar1.zRotation = .pi / 4; xBar1.position = CGPoint(x: 0, y: 20)
        node.addChild(xBar1)
        let xBar2 = SKShapeNode(rectOf: CGSize(width: 6, height: 28), cornerRadius: 3)
        xBar2.fillColor = SKColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
        xBar2.strokeColor = .clear; xBar2.zRotation = -.pi / 4; xBar2.position = CGPoint(x: 0, y: 20)
        node.addChild(xBar2)

        let body = SKPhysicsBody(rectangleOf: CGSize(width: 24, height: size.height))
        body.isDynamic          = false
        body.categoryBitMask    = catBarrier
        body.contactTestBitMask = catCapybara
        node.physicsBody        = body

        let move   = SKAction.moveBy(x: -(size.width * 2.4), y: 0, duration: Double(size.width * 2.4 / max(gameSpeed * 0.6, 150)))
        let remove = SKAction.removeFromParent()
        node.run(SKAction.sequence([move, remove]), withKey: "barrierMove")

        // Pulse warning
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        xBar1.run(SKAction.repeatForever(pulse))
        xBar2.run(SKAction.repeatForever(pulse))

        addChild(node)
    }

    // MARK: - Input

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard !isPaused_ else { return }

        switch gesture.direction {
        case .left  where currentLane > 0: currentLane -= 1
        case .right where currentLane < 2: currentLane += 1
        case .up where isOnGround:
            jump()
        default: break
        }

        // Slide to new lane
        let newX = size.width / 2 + laneXPositions[currentLane]
        let slide = SKAction.moveTo(x: newX, duration: 0.12)
        slide.timingMode = .easeInEaseOut
        capybara.run(slide)
    }

    private func jump() {
        isOnGround = false
        capybara.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 220))

        let squish = SKAction.sequence([
            SKAction.scaleY(to: 0.7, duration: 0.06),
            SKAction.scaleY(to: 1.3, duration: 0.10),
            SKAction.scaleY(to: 1.0, duration: 0.14)
        ])
        capyBody.run(squish)
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if masks == (catCapybara | catGround) {
            isOnGround = true
        }

        if masks == (catCapybara | catObstacle) {
            hitObstacle()
        }

        if masks == (catCapybara | catBarrier) {
            hitBarrier(contact)
        }
    }

    private func hitObstacle() {
        guard !isPaused_ else { return }
        // Flash red + shake
        let flash  = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.05),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.15)
        ])
        capyBody.run(flash)
        capybara.run(SKAction.sequence([
            SKAction.moveBy(x: -10, y: 0, duration: 0.05),
            SKAction.moveBy(x:  10, y: 0, duration: 0.05),
            SKAction.moveBy(x: -10, y: 0, duration: 0.05),
            SKAction.moveBy(x:  10, y: 0, duration: 0.05),
        ]))

        // Remove obstacles nearby to avoid double hits
        enumerateChildNodes(withName: "obstacle") { node, _ in
            if abs(node.position.x - (self.capybara?.position.x ?? 0)) < 100 {
                node.removeFromParent()
            }
        }

        DispatchQueue.main.async { self.state?.loseLife() }
    }

    private func hitBarrier(_ contact: SKPhysicsContact) {
        guard !isPaused_ else { return }
        isPaused_ = true

        // Stop the barrier
        let barrierNode = contact.bodyA.categoryBitMask == catBarrier ? contact.bodyA.node : contact.bodyB.node
        barrierNode?.removeAction(forKey: "barrierMove")

        // Pause scene speed (but keep physics running for capybara)
        speed = 0.0

        // Present question
        let q = nextQuestion()
        DispatchQueue.main.async {
            self.state?.presentQuestion(q)
        }
    }

    private func nextQuestion() -> FlowQuestion {
        guard !questions.isEmpty else { return DemoFlowQuestions.all[0] }
        let q = questions[questionIndex % questions.count]
        questionIndex += 1
        return q
    }

    // MARK: - Answer received

    @objc private func onAnswered(_ notification: Notification) {
        let correct = notification.userInfo?["correct"] as? Bool ?? false

        // Remove barrier
        enumerateChildNodes(withName: "barrier") { node, _ in
            let particles = SKEmitterNode()
            particles.position = node.position
            node.removeFromParent()
        }

        if correct {
            // Burst through — speed boost + green flash
            let burst = SKAction.sequence([
                SKAction.colorize(with: SKColor(red: 0.18, green: 0.72, blue: 0.49, alpha: 1), colorBlendFactor: 0.8, duration: 0.08),
                SKAction.colorize(withColorBlendFactor: 0, duration: 0.25)
            ])
            capyBody.run(burst)
            capybara.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 60))
            gameSpeed = min(gameSpeed + 30, 600)
        } else {
            // Wrong — red flash + slow briefly
            let flash = SKAction.sequence([
                SKAction.colorize(with: .red, colorBlendFactor: 0.9, duration: 0.08),
                SKAction.colorize(withColorBlendFactor: 0, duration: 0.25)
            ])
            capyBody.run(flash)
        }

        isPaused_ = false
        speed = 1.0
    }

    @objc private func onRestart() {
        removeAllChildren()
        removeAllActions()
        currentLane  = 1
        isOnGround   = true
        gameSpeed    = 350
        spawnTimer   = 0
        barrierTimer = 0
        scoreTimer   = 0
        questionIndex = 0
        isPaused_    = false
        speed        = 1.0
        buildQuestions()
        setupPhysics()
        setupBackground()
        setupGround()
        setupCapybara()
        barrierInterval = Double.random(in: 5...10)
    }
}
