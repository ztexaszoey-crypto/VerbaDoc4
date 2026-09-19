import SwiftUI
import Combine

// MARK: - Skin

struct CapySkin: Identifiable, Equatable {
    let id: String
    let name: String
    let bodyColor: (r: Double, g: Double, b: Double)
    let accentColor: (r: Double, g: Double, b: Double)
    let price: Int
    let accessory: SkinAccessory

    enum SkinAccessory { case none, crown, helmet, scarf, eyePatch, tie, armor }

    static func == (lhs: CapySkin, rhs: CapySkin) -> Bool { lhs.id == rhs.id }

    static let all: [CapySkin] = [
        CapySkin(id: "default",    name: "Cappy",           bodyColor: (0.65,0.50,0.35), accentColor: (0.55,0.40,0.25), price: 0,    accessory: .none),
        CapySkin(id: "business",   name: "Business Capy",   bodyColor: (0.55,0.55,0.60), accentColor: (0.35,0.35,0.40), price: 200,  accessory: .tie),
        CapySkin(id: "ninja",      name: "Ninja Capy",      bodyColor: (0.15,0.15,0.18), accentColor: (0.50,0.50,0.55), price: 350,  accessory: .scarf),
        CapySkin(id: "astronaut",  name: "Astronaut Capy",  bodyColor: (0.92,0.92,0.95), accentColor: (0.70,0.70,0.75), price: 500,  accessory: .helmet),
        CapySkin(id: "pirate",     name: "Pirate Capy",     bodyColor: (0.60,0.42,0.25), accentColor: (0.45,0.30,0.18), price: 600,  accessory: .eyePatch),
        CapySkin(id: "king",       name: "King Capy",       bodyColor: (0.80,0.60,0.20), accentColor: (0.70,0.50,0.10), price: 1000, accessory: .crown),
        CapySkin(id: "watermelon", name: "Watermelon King", bodyColor: (0.20,0.65,0.25), accentColor: (0.10,0.50,0.15), price: 2000, accessory: .armor),
    ]
}

// MARK: - Powerup
//
// Phase 21 extended the catalog from 4 to 8 cases. The `label` and
// `duration` switches are exhaustive so callers can rely on the
// compiler to surface a missing case at the next enum extension.
//
//   magnet       10s  -- attract nearby melons
//   shield        0s  -- absorbs one crash (toggle, decays via `hasShield` reset)
//   rocket        5s  -- forward thrust + dust trail
//   turbo         6s  -- global game-speed up + screen edge wind
//   headStart     8s  -- +25% juice at run-start (Phase 21)
//   doubleCoins   8s  -- 2x melon multiplier (Phase 21)
//   timeFreeze    6s  -- 0.5x obstacle speed (Phase 21)
//   brainBoost    8s  -- 2x score multiplier (Phase 21)
enum PowerupType: String, CaseIterable {
    case magnet, shield, rocket, turbo, headStart, doubleCoins, timeFreeze, brainBoost

    var label: String {
        switch self {
        case .magnet:      return "Magnet"
        case .shield:      return "Shield"
        case .rocket:      return "Rocket"
        case .turbo:       return "Turbo"
        case .headStart:   return "Head Start"
        case .doubleCoins: return "Double Coins"
        case .timeFreeze:  return "Time Freeze"
        case .brainBoost:  return "Brain Boost"
        }
    }
    var duration: Double {
        switch self {
        case .magnet:      return 10
        case .shield:      return 0
        case .rocket:      return 5
        case .turbo:       return 6
        case .headStart:   return 8
        case .doubleCoins: return 8
        case .timeFreeze:  return 6
        case .brainBoost:  return 8
        }
    }
}

// MARK: - Study Challenge (6 kinds)
//
// Replaces the original CapySurfersQuestion. Each instance is tied to either
// a StudyItem from the user's deck (for SM-2 mastery writeback) or nil when
// running the Demo deck. `verify(_:)` checks the user's answer for the kind
// and surfaces the SM-2 writeback via CapySurfersState.endRun().
//
struct StudyChallenge: Identifiable {
    let id        : UUID
    let kind      : ChallengeKind
    let prompt    : String
    let topic     : String
    let itemID    : String?    // StudyItem.id if tied; nil for demo
    let isBonus   : Bool

    enum ChallengeKind {
        case multipleChoice(options: [String], correctIndex: Int)
        case trueFalse(isTrue: Bool)
        case flashcardRecall(answer: String)
        case imageQuestion(symbol: String, options: [String], correctIndex: Int)
        case diagramID(symbol: String, options: [String], correctIndex: Int)
        case matchTheTerm(pairs: [(String, String)])   // [(term, definition)]

        var displayName: String {
            switch self {
            case .multipleChoice:    return "Multiple Choice"
            case .trueFalse:         return "True / False"
            case .flashcardRecall:   return "Flashcard Recall"
            case .imageQuestion:     return "Image Question"
            case .diagramID:         return "Diagram"
            case .matchTheTerm:      return "Match the Term"
            }
        }
    }

    init(kind: ChallengeKind, prompt: String, topic: String, itemID: String?, isBonus: Bool) {
        self.id      = UUID()
        self.kind    = kind
        self.prompt  = prompt
        self.topic   = topic
        self.itemID  = itemID
        self.isBonus = isBonus
    }

    enum Answer {
        case index(Int)                // for multipleChoice / imageQuestion / diagramID
        case bool(Bool)                // for trueFalse
        case revealed                  // for flashcardRecall (always counts as correct)
        case pairs([String: String])    // for matchTheTerm (definition-by-term)
    }

    func verify(_ answer: Answer) -> Bool {
        switch (kind, answer) {
        case let (.multipleChoice(_, ci),  .index(i)):   return i == ci
        case let (.trueFalse(flag),       .bool(b)):     return b == flag
        case let (.imageQuestion(_,_,ci), .index(i)):    return i == ci
        case let (.diagramID(_,_,ci),     .index(i)):    return i == ci
        case (.flashcardRecall,           .revealed):    return true
        case let (.matchTheTerm(pairs),   .pairs(map)):
            guard map.count == pairs.count else { return false }
            for (term, def) in pairs where map[term] != def { return false }
            return true
        default:
            return false
        }
    }
}

// Legacy alias kept for any external callers. Internally wrapped into
// StudyChallenge.multipleChoice below by the builder helper.
//
typealias CapySurfersQuestion = StudyChallenge
extension CapySurfersQuestion {
    static func legacy(_ q: String, choices: [String], correctIndex: Int) -> CapySurfersQuestion {
        .init(kind: .multipleChoice(options: choices, correctIndex: correctIndex),
              prompt: q, topic: "", itemID: nil, isBonus: false)
    }
    var choices: [String] {
        if case let .multipleChoice(o, _) = kind { return o }
        return []
    }
    var correctIndex: Int {
        if case let .multipleChoice(_, i) = kind { return i }
        return 0
    }
    /// Backwards-compat: pre-rename code reads `q.question`.
    var question: String { prompt }
}

// MARK: - Game State

final class CapySurfersState: ObservableObject {

    /// Singleton accessor. Used by global lookup helpers (e.g.
    /// `CapyMissionEngine.claimable`) that don't have direct access to
    /// an @EnvironmentObject instance. Initialising this triggers
    /// `init() → bootstrap()`, which is harmless — `bootstrap()` only
    /// resets `@Published` session state and calls `refillBankFromJuice`,
    /// neither of which reads any contextual state.
    static let shared = CapySurfersState()

    // ── Persistent ──────────────────────────────────────────────────────────
    @AppStorage("capyHighScore")       var highScore:        Int    = 0
    @AppStorage("capyWatermelons")     var totalMelons:      Int    = 0
    @AppStorage("capyOwnedSkins")      var ownedSkinIDs:     String = "default"
    @AppStorage("capyEquippedSkin")    var equippedID:       String = "default"
    // Phase 15 — gate + bankedSeconds slots. preGameGateSeen flips true
    // once the user completes the pre-run refuel quiz so we don't show
    // the gate on every open. bankedSeconds is the off-game tank the
    // top-up button refills; the capy drains bankedSeconds when entering
    // a run.
    @AppStorage("capyPreGameGateSeen") var preGameGateSeen:  Bool   = false
    @AppStorage("capyBankedSeconds")   var bankedSeconds:    Double = 0

    // Phase 21: daily-mission state. Three lightweight keys back the
    // deterministic per-day mission picker + progress counter + claim
    // timestamp (so the same mission is shown across all launches the
    // same day, and a player can't double-claim the reward within the
    // same day).
    @AppStorage("capyDailyMissionID")        var dailyMissionID:        String = ""
    @AppStorage("capyDailyMissionDate")      var dailyMissionDate:      String = ""
    @AppStorage("capyDailyMissionProgress")  var dailyMissionProgress:  Int    = 0
    @AppStorage("capyDailyMissionClaimedAt") var dailyMissionClaimedAt: String = ""


    // MARK: - Phase 21: Power-up multiplier runtime state
    //
    // The Scene reads `scoreMultiplier` / `melonMultiplier` /
    // `speedMultiplier` to apply per-collect harvest effects. These
    // are plain `var` (NOT @Published) because the Scene drives them
    // — SwiftUI doesn't observe harvest loops at SpriteKit tick
    // resolution, and the HUD shows the harvested totals (combo /
    // xpEarnedThisRun) instead of the multipliers per-frame.
    //
    //   activePowerup / powerupEndsAt intentionally NOT redeclared
    //   here. The @Published versions in the Session block below are
    //   the single source of truth — SwiftUI views observe them for
    //   the powerup HUD pill + countdown. The Scene also reads/writes
    //   the same fields through the singleton.
    var scoreMultiplier: Int = 1
    var melonMultiplier: Int = 1
    var speedMultiplier: Double = 1.0

    // ── Phase 15 — Refuel & Surf seconds-model constants ───────────────────
    // User clarification: +5 seconds per correct, -5 seconds per wrong,
    // 0 seconds for partial reveal (flashcardRecall). Drain runs at -1
    // s/s while the capy is on the tracks, so the cap on a 30s tank
    // gives roughly 30 seconds of free play between refuel pauses.
    static let secondsCap:        Double = 30
    static let secondsPerCorrect: Double = 5
    static let secondsPerWrong:   Double = 5
    static let secondsPerPartial: Double = 0

    // ── Session ─────────────────────────────────────────────────────────────
    @Published var distance:       Int    = 0
    @Published var melonsThisRun:  Int    = 0
    @Published var isGameOver:     Bool   = false
    @Published var isNewHighScore: Bool   = false

    // Focus (formerly "energy") — Phase 5 Refuel & Surf:
    //   • juice starts at 0 — player must warm up before running
    //   • drains deterministically at -1%/s (10%/10s) until 0
    //   • at 0 the scene FREEZES and needsRefuel flips true
    //   • refuel cycle: 3 correct answers refills juice to 100
    //   • legacy `energy` field remains as an alias so existing callers
    //     compile unchanged; new logic exclusively uses `juice`.
    @Published var juice:        Double = 0
    @Published var juiceFlash:   Bool   = false

    /// Backwards-compat alias for the old `energy` token. New code should
    /// read `state.juice` directly; this shim keeps the SM-2 mastery
    /// writeback helpers and the old `submit(_:)` body compiling without
    /// having to rewrite every reference.
    var energy: Double {
        get { juice }
        set { juice = newValue }
    }
    var energyFlash: Bool {
        get { juiceFlash }
        set { juiceFlash = newValue }
    }

    // Refuel state machine (Phase 5)
    @Published var preRunWarmup:    Bool   = true     // launched game starts here at juice=0
    @Published var needsRefuel:     Bool   = false    // juice==0 mid-run → FREEZE
    @Published var refuelProgress:  Int    = 0        // 0...3 — refuel cycle counter
    @Published var refuelTarget:    Int    = 3        // questions to refill
    @Published var isCountingDown:  Bool   = false    // 3-2-1 visible after correct refuel
    @Published var countdownStep:   Int    = 0        // 0..3 (0 = "3", 1 = "2", ...)

    // Powerup
    @Published var activePowerup:   PowerupType? = nil
    @Published var powerupTimeLeft: Double = 0
    @Published var hasShield:       Bool = false

    // Study challenge (6 kinds)
    @Published var quizActive       : Bool              = false
    @Published var currentChallenge : StudyChallenge?   = nil
    @Published var lastAnswer       : StudyChallenge.Answer? = nil
    @Published var challengeResolved : Bool              = false
    @Published var lastSubmitCorrect : Bool?             = nil  // used by GameView border color (works for any kind)

    // Combo / progression
    @Published var combo           : Int = 0
    @Published var bestComboThisRun: Int = 0
    @Published var lastXPBoost     : Int = 0      // for "+XP" pulse animation
    @Published var xpEarnedThisRun : Int = 0
    @Published var cardsReviewedThisRun: Int = 0
    @Published var itemsCorrectThisRun : Int = 0
    @Published var streakCreditedThisRun: Bool = false

    // ── Internal ────────────────────────────────────────────────────────────
    private(set) var questionPool: [StudyItem] = []
    private var touchedItemIDs: Set<String> = []
    private var touchedCorrectness: [String: Bool] = [:]   // itemID -> was it ever answered correctly

    // ── Backwards-compat shim for callers using state.quizQuestion ───────────
    var quizQuestion: StudyChallenge? { currentChallenge }
    var quizAnswered: Int? {
        guard let last = lastAnswer else { return nil }
        if case let .index(i) = last { return i }
        return nil
    }
    var quizIsBonus: Bool { currentChallenge?.isBonus ?? false }

    // ── Computed ────────────────────────────────────────────────────────────
    var equippedSkin: CapySkin { CapySkin.all.first { $0.id == equippedID } ?? CapySkin.all[0] }
    var ownedSkins: Set<String> { Set(ownedSkinIDs.components(separatedBy: ",")) }

    func owns(_ skin: CapySkin) -> Bool { ownedSkins.contains(skin.id) }

    func buy(_ skin: CapySkin) -> Bool {
        guard totalMelons >= skin.price, !owns(skin) else { return false }
        totalMelons -= skin.price
        ownedSkinIDs += ",\(skin.id)"
        return true
    }

    func equip(_ skin: CapySkin) {
        guard owns(skin) else { return }
        equippedID = skin.id
    }

    // ── Setup ───────────────────────────────────────────────────────────────
    func loadQuestions(from documents: [Document]) {
        questionPool = documents.flatMap(\.studyItems)
            .filter { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // ── Session control ─────────────────────────────────────────────────────
    func startRun() {
        distance             = 0
        melonsThisRun        = 0
        isGameOver           = false
        isNewHighScore       = false
        activePowerup        = nil
        powerupTimeLeft      = 0
        hasShield            = false
        // Phase 15: bankedSeconds is the off-game tank the top-up button
        // refills. The cap enters the run with whatever tank value the
        // user banked; gate completion guarantees `secondsCap`.
        energy               = bankedSeconds
        // Phase 16.5 freeze trigger. When the bank is empty (fresh
        // install, post-crash restart, or skip-the-gate flow) the
        // refuel overlay needs to fire IMMEDIATELY. tickJuice's
        // `prev > 0 && juice == 0` predicate only catches mid-run
        // drain-to-zero, so we set needsRefuel here for the
        // at-start-at-zero path. preRunWarmup=false so the refuel
        // overlay renders the mid-game variant (not the gate variant).
        if energy == 0 {
            needsRefuel    = true
            preRunWarmup   = false
            refuelProgress = 0
        }
        energyFlash          = false
        quizActive           = false
        currentChallenge     = nil
        lastAnswer         = nil
        challengeResolved  = false
        lastSubmitCorrect  = nil
        combo             = 0
        bestComboThisRun  = 0
        lastXPBoost       = 0
        xpEarnedThisRun      = 0
        cardsReviewedThisRun = 0
        itemsCorrectThisRun  = 0
        streakCreditedThisRun = false
        touchedItemIDs       = []
        touchedCorrectness   = [:]
    }

    func addDistance(_ d: Int) { distance += d }
    func collectMelon() {
        melonsThisRun += 1
        // Each melon grants 1 XP equivalent for combo scaling — visual only,
        // applied to lastXPBoost for HUD pulse.
        lastXPBoost = 1
    }

    func activatePowerup(_ type: PowerupType) {
        activePowerup   = type
        powerupTimeLeft = type.duration
        if type == .shield { hasShield = true }
    }

    func tickPowerup(dt: Double) {
        guard let p = activePowerup, p != .shield else { return }
        powerupTimeLeft -= dt
        if powerupTimeLeft <= 0 { activePowerup = nil }
    }

    // ── Juice (Phase 5 — deterministic -1%/s drain + freeze-trigger) ───────

    /// Called by the scene every frame while running. Drains juice at
    /// `drainRate / 10` per second (i.e. 10%/10s). Returns true on the
    /// frame juice crossed 0 → 0; the caller (scene) then halts updates
    /// because the state already flipped `needsRefuel = true` and posted
    /// `.capyRefuelTriggered` so SpriteKit pauses via the observer.
    @discardableResult
    func tickJuice(dt: Double) -> Bool {
        guard !needsRefuel, !isGameOver, !isCountingDown,
              !preRunWarmup, !quizActive else { return false }
        let prev = juice
        juice = max(0, juice - (1.0 * dt))     // 1%/sec
        // Phase 16 — bankedSeconds (off-game tank the top-up button
        // refills) drains IN LOCKSTEP with juice so an empty mid-run
        // tank ↔ empty post-run bank. Without this the player could
        // drain to 0s, exit, and re-enter with a free full tank because
        // bankedSeconds was left at the post-refuel value.
        bankedSeconds = max(0, bankedSeconds - (1.0 * dt))
        if prev > 0 && juice == 0 {
            needsRefuel = true
            // Clear any in-flight challenge so the overlay can take over.
            quizActive          = false
            currentChallenge    = nil
            lastAnswer          = nil
            challengeResolved   = false
            lastSubmitCorrect   = nil
            refuelProgress      = 0   // fresh refuel cycle begins at 0/3
            HapticManager.error()
            NotificationCenter.default.post(name: .capyRefuelTriggered, object: nil)
            return true
        }
        return false
    }

    /// Backwards-compat alias for the pre-Phase-5 `drainEnergy` callers
    /// (CapySurfersScene may still pass the old `speed:` argument during
    /// the migration). Maps to `tickJuice` after dropping the now-unused
    /// speed dependency.
    @discardableResult
    func drainEnergy(dt: Double, speed: CGFloat) -> Bool {
        return tickJuice(dt: dt)
    }

    func flashLowJuice() {
        juiceFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.juiceFlash = false }
    }

    /// Backwards-compat for HUD flashing code that still calls flashLowEnergy.
    func flashLowEnergy() { flashLowJuice() }

    // ── Refuel cycle lifecycle (Phase 5) ──────────────────────────────────────

    /// Called by the RefuelOverlay to feed a refuel-mode answer.
    /// Adds +25% juice on correct; otherwise no juice change. Awards SM-2
    /// writeback regardless of correctness so the learning signal is
    /// preserved. When `refuelProgress` hits `refuelTarget`, the overlay
    /// observes that and starts the 3-2-1 countdown via `beginCountdown()`.
    func submitRefuel(_ answer: StudyChallenge.Answer) {
        guard needsRefuel, let c = currentChallenge, !challengeResolved else { return }
        let correct = c.verify(answer)
        lastAnswer        = answer
        challengeResolved = true
        lastSubmitCorrect = correct
        cardsReviewedThisRun += 1
        // SM-2 writeback — every refuel-mode question is logged.
        if let id = c.itemID {
            touchedItemIDs.insert(id)
            touchedCorrectness[id, default: false] = touchedCorrectness[id] == true || correct
        }
        // Phase 15: per-kind energy delta.
        //   flashcardRecall.reveal  →  0 s (user brief: "none for partial")
        //   correct .non-reveal     →  +5 s
        //   wrong                   →  -5 s
        let isPartialReveal: Bool = {
            guard case .flashcardRecall = c.kind, case .revealed = answer else { return false }
            return true
        }()
        let correctDelta: Double = isPartialReveal ? Self.secondsPerPartial : Self.secondsPerCorrect
        if correct {
            itemsCorrectThisRun += 1
            combo += 1
            bestComboThisRun = max(bestComboThisRun, combo)
            juice = max(0, min(Self.secondsCap, juice + correctDelta))
            refuelProgress  += 1
            HapticManager.success()
        } else {
            combo = 0
            juice = max(0, juice - Self.secondsPerWrong)
            HapticManager.impact(.medium)
        }
    }

    /// Serves the next refuel question after the 1.1s feedback window.
    /// Called from the RefuelOverlay's onAppear-of-next-question chain.
    func serveNextRefuelQuestion() {
        guard needsRefuel else { return }
        challengeResolved = false
        currentChallenge  = buildChallenge(bonus: false)
        quizActive        = true
    }

    /// Triggered by the RefuelOverlay when 3 correct answers are in.
    /// Flips `isCountingDown` true; the GameView's countdown timer advances
    /// `countdownStep` from 0 ("3") to 3 ("GO!") at 1-second intervals and
    /// calls `commitRefuel()` when it lands on 3.
    func beginCountdown() {
        isCountingDown = true
        countdownStep  = 0
    }

    /// Final step of the countdown. Resets refuel state, fills juice, and
    /// posts `.capyResume` so SpriteKit re-takes the update loop.
    func commitRefuel() {
        needsRefuel     = false
        refuelProgress  = 0
        isCountingDown  = false
        countdownStep   = 0
        juice           = min(juice, Self.secondsCap)   // refresh to ≤ cap
        juice           = Self.secondsCap                // full bar
        preRunWarmup    = false                          // allow scene drain loop to run
        currentChallenge = nil
        quizActive      = false
        lastAnswer      = nil
        challengeResolved = false
        refillBankFromJuice()                           // bank the freshly-filled tank
        NotificationCenter.default.post(name: .capyResume, object: nil)
    }

    /// Failure path: user dismissed the refuel overlay mid-cycle. Treat as
    /// end-of-run so high-score + melon wallet are saved.
    func failRefuel() {
        needsRefuel    = false
        isCountingDown = false
        refuelProgress = 0
        endRun()
    }

    /// Pre-run warmup completion — supplies juice when the player finishes
    /// the warmup round. Called by the RefuelOverlay at the end of the
    /// pre-game gate's 3-question cycle.
    /// Pre-run warmup completion — supplies juice when the player finishes
    /// the warmup round. Called by the RefuelOverlay at the end of the
    /// pre-game gate's 3-question cycle.
    func completePreRunWarmup() {
        juice          = Self.secondsCap
        refillBankFromJuice()           // bank the freshly-filled tank
        preRunWarmup   = false
        preGameGateSeen = true
        NotificationCenter.default.post(name: .capyResume, object: nil)
    }

    /// Phase 16.5 polish — single helper for the
    /// "juice was just filled, mirror it into the off-game bank" pattern.
    /// Replaces duplicate `bankedSeconds = juice` writes that previously
    /// lived in `commitRefuel()` and `completePreRunWarmup()`. Top-up
    /// flows use a different keep-bigger wrote and intentionally do not
    /// call this helper.
    private func refillBankFromJuice() {
        bankedSeconds = juice
    }

    // ── Challenge lifecycle ─────────────────────────────────────────────────

    /// Build a study challenge. Randomly picks one of the 6 kinds based on
    /// what the loaded questionPool supports. Falls back to MCQ for demo runs.
    func triggerChallenge(bonus: Bool) {
        guard !quizActive else { return }
        let challenge = buildChallenge(bonus: bonus)
        currentChallenge  = challenge
        lastAnswer        = nil
        challengeResolved = false
        quizActive        = true
    }

    /// Backwards-compat alias — CapySurfersScene still calls the old name.
    func triggerQuiz(bonus: Bool) { triggerChallenge(bonus: bonus) }

    private func buildChallenge(bonus: Bool) -> StudyChallenge {
        let pool = questionPool.shuffled()

        // Demo deck fallback: no real StudyItems loaded. DemoTrivia always
        // ships with 3 distinct distractors so the MCQ happy-path is
        // guaranteed and the makeMCQ defensive padding is a no-op here.
        guard let item = pool.first else {
            return demokDeckMCQ(bonus: bonus)
        }

        // Hoisted once: pool/sufficientDistractors are loop-invariant across
        // the up-to-3 re-rolls. ≥ 3 distinct non-correct distractors required
        // by makeMCQ / makeImagePick / makeDiagram to produce a question with
        // ZERO ghost em-dash placeholders (those builders pad only up to 3,
        // so 2 distinct candidates still leaves one padded slot).
        let sufficientDistractors = hasEnoughDistractors(for: item)

        // Re-roll up to 3 times when a chosen kind lacks enough supporting data:
        //
        //   .multipleChoice / .imageQuestion / .diagramID — need ≥ 3 unique
        //     non-correct distractors in the pool, otherwise the question
        //     shows ghost em-dash placeholders that look broken.
        //   .matchTheTerm            — needs ≥ 3 StudyItems total for pairs.
        //
        // .trueFalse and .flashcardRecall always work from a single item, so
        // they short-circuit on the first roll. After 3 unrewarding rolls,
        // we fall back to flashcard so the player *always* sees a real
        // learning interaction (and so their StudyItem mastery still writes
        // back via SM-2).
        for _ in 0..<3 {
            let kindRoll = Int.random(in: 0...99)
            switch kindRoll {
            case 0..<35:
                if sufficientDistractors {
                    return makeMCQ(from: item, bonus: bonus)
                }
            case 35..<60:
                return makeTrueFalse(from: item, bonus: bonus)
            case 60..<75:
                return makeFlashcard(from: item, bonus: bonus)
            case 75..<88:
                if sufficientDistractors {
                    return makeImagePick(from: item, bonus: bonus)
                }
            case 88..<95:
                if sufficientDistractors {
                    return makeDiagram(from: item, bonus: bonus)
                }
            default:
                if pool.count >= 3 {
                    // Array(...) wrap for type stability — same shape makeMCQ
                    // applies, so a future change to ArraySlice semantics
                    // doesn't risk a regression here either.
                    return makeMatchTheTerm(from: Array(pool.prefix(3)), bonus: bonus)
                }
            }
        }
        // Fallback after 3 unrewarding re-rolls. We bias toward TrueFalse
        // over Flashcard because TrueFalse tests *discrimination* (does the
        // user's prior memory match the statement?) while Flashcard is pure
        // recall-and-reveal. When the deck is thin, discrimination is the
        // higher-leverage learning interaction.
        return makeTrueFalse(from: item, bonus: bonus)
    }

    /// Returns true if the questionPool has at least 3 unique non-correct
    /// truncated-answer candidates that can serve as distractors for the
    /// MCQ-style kinds (.multipleChoice, .imageQuestion, .diagramID).
    /// 3 is the minimum that lets those builders produce a 4-option question
    /// with NO em-dash padding (they pad while count < 3 then append correct).
    /// .trueFalse and .flashcardRecall do not call this.
    private func hasEnoughDistractors(for item: StudyItem) -> Bool {
        let correct = truncated(item.answer)
        let distinctNonCorrect = Set(
            questionPool
                .filter { $0.id != item.id }
                .map { truncated($0.answer) }
                .filter { $0 != correct }
        )
        return distinctNonCorrect.count >= 3
    }

    /// Build a demo-deck multiple choice. Used when the user has no real
    /// StudyItems to study. Returns a guaranteed 4-option question with 3
    /// distinct distractors from the bundled DemoTrivia pool.
    private func demokDeckMCQ(bonus: Bool) -> StudyChallenge {
        let trivia = DemoTrivia.random()
        return makeMCQ(from: trivia.prompt, correct: trivia.answer,
                       distractors: trivia.distractors, topic: trivia.topic,
                       itemID: nil, bonus: bonus)
    }

    // ── Challenge builders ──────────────────────────────────────────────────

    private func makeMCQ(from item: StudyItem, bonus: Bool) -> StudyChallenge {
        let correct = truncated(item.answer)
        let distractors = questionPool
            .filter { $0.id != item.id }
            .shuffled()
            .prefix(3)
            .map { truncated($0.answer) }
        return makeMCQ(from: item.question, correct: correct, distractors: Array(distractors),
                       topic: item.topic, itemID: item.id, bonus: bonus)
    }

    private func makeMCQ(from prompt: String, correct: String, distractors: [String], topic: String, itemID: String?, bonus: Bool) -> StudyChallenge {
        // De-dupe distractors against `correct` first: deck answers are short
        // snippets and overlap between StudyItems is common. Without this, the
        // same string can end up in `opts` twice and `firstIndex(of: correct)`
        // would return the wrong slot, handing the player a free win.
        //
        // Pad the distractor pool back up to 3 with the em-dash sentinel so
        // players with tiny decks (1–3 unique answers) still get a 4-option
        // question. `swapAt(3, ci)` then requires `opts.count == 4`.
        var opts = Array(distractors.filter { $0 != correct }.prefix(3))
        while opts.count < 3 { opts.append("\u{2014}") }   // pad up to 3 distractors
        opts.append(correct)                               // opts.count is now exactly 4
        let ci = Int.random(in: 0...3)                     // shuffle `correct` into a random slot
        opts.swapAt(3, ci)                                 // correct can no longer be at index 3
        return .init(kind: .multipleChoice(options: opts, correctIndex: ci),
                     prompt: prompt, topic: topic, itemID: itemID, isBonus: bonus)
    }

    private func makeTrueFalse(from item: StudyItem, bonus: Bool) -> StudyChallenge {
        let flag = Double.random(in: 0...1) < 0.70   // 70% the statement is true
        return .init(kind: .trueFalse(isTrue: flag),
                     prompt: "True or False: " + item.question,
                     topic: item.topic, itemID: item.id, isBonus: bonus)
    }

    private func makeFlashcard(from item: StudyItem, bonus: Bool) -> StudyChallenge {
        return .init(kind: .flashcardRecall(answer: item.answer),
                     prompt: item.question, topic: item.topic, itemID: item.id, isBonus: bonus)
    }

    private func makeImagePick(from item: StudyItem, bonus: Bool) -> StudyChallenge {
        // Same de-dupe + pad-to-4 dance as makeMCQ but for imageQuestion kind.
        let symbol = VerbaChallengeIcons.symbol(for: item.answer.first ?? "a")
        let correct = truncated(item.answer)
        var opts = Array(
            questionPool
                .filter { $0.id != item.id }
                .shuffled()
                .prefix(3)
                .map { truncated($0.answer) }
                .filter { $0 != correct }
        )
        while opts.count < 3 { opts.append("\u{2014}") }
        opts.append(correct)               // opts.count == 4 guaranteed
        let ci = Int.random(in: 0...3)
        opts.swapAt(3, ci)
        return .init(kind: .imageQuestion(symbol: symbol, options: opts, correctIndex: ci),
                     prompt: "Which matches: '" + item.question + "'?",
                     topic: item.topic, itemID: item.id, isBonus: bonus)
    }

    private func makeDiagram(from item: StudyItem, bonus: Bool) -> StudyChallenge {
        let symbol = VerbaChallengeIcons.diagramSymbol(for: item.topic)
        let correct = truncated(item.answer)
        var opts = Array(
            questionPool
                .filter { $0.id != item.id }
                .shuffled()
                .prefix(3)
                .map { truncated($0.answer) }
                .filter { $0 != correct }
        )
        while opts.count < 3 { opts.append("\u{2014}") }
        opts.append(correct)               // opts.count == 4 guaranteed
        let ci = Int.random(in: 0...3)
        opts.swapAt(3, ci)
        return .init(kind: .diagramID(symbol: symbol, options: opts, correctIndex: ci),
                     prompt: "Identify the diagram for: '" + item.question + "'",
                     topic: item.topic, itemID: item.id, isBonus: bonus)
    }

    private func makeMatchTheTerm<S: Sequence>(from items: S, bonus: Bool) -> StudyChallenge where S.Element == StudyItem {
        let chosen = Array(items.prefix(3))
        let pairs = chosen.map { ($0.question.trimmingCharacters(in: .whitespacesAndNewlines),
                                  truncated($0.answer)) }
        let topic = chosen.first?.topic ?? "Mixed"
        let itemID = chosen.first?.id
        return .init(kind: .matchTheTerm(pairs: pairs),
                     prompt: "Match each term with its definition.",
                     topic: topic, itemID: itemID, isBonus: bonus)
    }

    private func truncated(_ text: String, limit: Int = 80) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // ── Submit answers ──────────────────────────────────────────────────────
    //
    // Replaces the old `answerQuiz(index:)`. The caller passes the typed
    // answer; the state verifies it, updates combo, schedules feedback, and
    // logs the item for SM-2 writeback at endRun().
    //

    func submit(_ answer: StudyChallenge.Answer) {
        guard let c = currentChallenge, !challengeResolved else { return }
        let correct = c.verify(answer)
        lastAnswer        = answer
        challengeResolved = true
        lastSubmitCorrect = correct
        cardsReviewedThisRun += 1

        // Track item for SM-2 writeback
        if let id = c.itemID {
            touchedItemIDs.insert(id)
            touchedCorrectness[id, default: false] = touchedCorrectness[id] == true || correct
        }

        // Phase 15: per-kind energy delta. Cap floor at 0 so a wrong answer
        // can't tunnel the capy into negative seconds; cap ceiling at
        // secondsCap so a streak of correct answers tops out cleanly.
        let isPartialReveal: Bool = {
            guard case .flashcardRecall = c.kind, case .revealed = answer else { return false }
            return true
        }()
        let correctDelta: Double = isPartialReveal ? Self.secondsPerPartial : Self.secondsPerCorrect
        if correct {
            itemsCorrectThisRun += 1
            combo += 1
            bestComboThisRun = max(bestComboThisRun, combo)
            energy = max(0, min(Self.secondsCap, energy + correctDelta))

            // Visual XP pulse for HUD (combo-scaled). Reveals give flat 1×
            // (no compounding combo on a "read the answer" path), real
            // answers compound as before.
            let boost = isPartialReveal ? 5 : 5 + combo * 2
            lastXPBoost = boost
            xpEarnedThisRun += boost
            HapticManager.success()
        } else {
            combo = 0
            energy = max(0, energy - Self.secondsPerWrong)
            lastXPBoost = 0
            HapticManager.impact(.medium)
        }

        // Auto-dismiss after a short feedback window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.quizActive        = false
            self?.currentChallenge  = nil
            self?.lastAnswer        = nil
            self?.challengeResolved = false
            NotificationCenter.default.post(name: .capyResume, object: nil)
        }
    }

    // ── End-of-run progression hooks ──────────────────────────────────────
    //
    // Two-stage end-of-run:
    //   • Scene calls `endRun()` on crash — finishes the melon/score book-keeping
    //     and flips isGameOver. No services needed (Scene is not a SwiftUI View).
    //   • GameView observes isGameOver → true and calls `endRun(xpManager:streakManager:)`
    //     to credit session XP and update the daily streak.
    // Both methods are idempotent via `isGameOver` so out-of-order calls are safe.
    //

    /// Record items that were answered during this run AND whether they were
    /// ever answered correctly. The Results view consumes this list to apply
    /// SM-2-lite mastery updates.
    var touchedItemsReview: [(itemID: String, everCorrect: Bool)] {
        touchedItemIDs.map { ($0, touchedCorrectness[$0] ?? false) }
    }

    /// Called by CapySurfersScene on player crash. Updates melon wallet and
    /// high-score, then signals game-over via `isGameOver = true`.
    func endRun() {
        guard !isGameOver else { return }
        totalMelons   += melonsThisRun
        if distance > highScore { highScore = distance; isNewHighScore = true }
        isGameOver     = true
        bankedSeconds = 0
        NotificationCenter.default.post(name: .capyRunEnded, object: nil)
    }

    /// Called by CapySurfersGameView (which owns the EnvironmentObjects) when
    /// it observes `isGameOver == true`. Awards the per-session XP grant and
    /// records today's study session for the streak.
    func endRun(xpManager: XPManager?, streakManager: StreakManager?) {
        guard isGameOver else { return }
        guard !streakCreditedThisRun else { return }
        xpManager?.award(.studySession)
        streakManager?.recordStudySession()
        streakCreditedThisRun = true
    }

    // ── Notifications to scene ─────────────────────────────────────────────
    func resumeGame() { NotificationCenter.default.post(name: .capyResume, object: nil) }
    func restartGame() {
        startRun()
        NotificationCenter.default.post(name: .capyRestart, object: nil)
    }
}

// MARK: - SF Symbol helpers
//
// Map alphabetical first letters / topic keywords to SF Symbols so we can
// ship Image Question + Diagram Identification without requiring image
// assets. The mapping is intentionally generic — matches VerbaDoc's
// "transform don't clone" rule and avoids holding copyrighted artwork.
//
enum VerbaChallengeIcons {
    static func symbol(for char: Character) -> String {
        let lowered = String(char).lowercased()
        switch lowered {
        case let s where "aeiou".contains(s): return "leaf.fill"
        case let s where "bcdfghjklmnpqrstvwxyz".contains(s): return "lightbulb.fill"
        default: return "questionmark.circle.fill"
        }
    }
    static func diagramSymbol(for topic: String) -> String {
        let t = topic.lowercased()
        if t.contains("math") || t.contains("calc") { return "function" }
        if t.contains("bio") || t.contains("anat") { return "atom" }
        if t.contains("chem")                       { return "flask" }
        if t.contains("history") || t.contains("geo") { return "globe.europe.africa.fill" }
        if t.contains("music") || t.contains("art") { return "paintpalette.fill" }
        if t.contains("lit") || t.contains("eng")  { return "text.book.closed.fill" }
        if t.contains("cs") || t.contains("code")  { return "curlybraces" }
        return "diagram.tree"
    }
}

// MARK: - Demo Trivia
//
// Used when the player has no real StudyItem decks loaded.
//
enum DemoTrivia {
    struct Q { let prompt: String; let answer: String; let distractors: [String]; let topic: String }
    static let all: [Q] = [
        Q(prompt: "What does RAM stand for?",
          answer: "Random Access Memory",
          distractors: ["Read Access Mode", "Runtime Array Module", "Rapid Action Memory"],
          topic: "Tech"),
        Q(prompt: "What planet is closest to the Sun?",
          answer: "Mercury",
          distractors: ["Venus", "Earth", "Mars"],
          topic: "Science"),
        Q(prompt: "Who wrote Romeo and Juliet?",
          answer: "William Shakespeare",
          distractors: ["Charles Dickens", "Jane Austen", "Homer"],
          topic: "Literature"),
        Q(prompt: "What is 7 × 8?",
          answer: "56",
          distractors: ["54", "63", "48"],
          topic: "Math"),
        Q(prompt: "What is H₂O?",
          answer: "Water",
          distractors: ["Hydrogen", "Helium", "Oxygen"],
          topic: "Chemistry"),
    ]
    static func random() -> Q { all.randomElement()! }
}

// MARK: - Notifications

extension Notification.Name {
    static let capyResume         = Notification.Name("capyResume")
    static let capyRestart        = Notification.Name("capyRestart")
    static let capyQuizStart      = Notification.Name("capyQuizStart")
    static let capyRunEnded       = Notification.Name("capyRunEnded")
    static let capyXpBoost        = Notification.Name("capyXpBoost")
    // Phase 5 (Refuel & Surf): posted when juice hits 0 mid-run. The
    // CapySurfersScene observes this and pauses the SKView so the
    // RefuelOverlay can serve its 3-question cycle. Companion to
    // `.capyResume`, which is posted when commitRefuel() /
    // completePreRunWarmup() fills the juice bar back up.
    static let capyRefuelTriggered = Notification.Name("capyRefuelTriggered")
}
