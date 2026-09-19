import SwiftUI
import SpriteKit
import SwiftData

// MARK: - CapySurfersGameView
// Hosts:
//   - 3-lane SpriteKit perspective runner (CapySurfersScene)
//   - HUD: distance, combo chip, focus bar, powerup, swipe hints
//   - Challenge overlay: dispatches on StudyChallenge.kind (6 study kinds)
//   - Results overlay wired to XPManager.award(.studySession) +
//     StreakManager.recordStudySession() on game-over.
//   - SM-2-lite mastery writeback runs in CapySurfersResultsView via @Query.

struct CapySurfersGameView: View {
    @StateObject private var state = CapySurfersState()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var xpManager   : XPManager
    @EnvironmentObject private var streakManager : StreakManager
    // SwiftData writes happen in CapySurfersResultsView (it owns the per-deck
    // mastery SM-2 writeback via @Query + modelContext). The view itself does
    // not need a ModelContext.
    @State private var showShop   = false
    @State private var sceneHolder = SceneHolder()
    // Phase 15 — pre-game gate. Fires on first .onAppear of the game
    // view (deliberately offset from `preGameGateSeen` so we can route
    // the dismiss path to state.startRun() after the user's three answers
    // are in even if the closure was previously flipped).
    @State private var showPreGameGate = false

    var documents: [Document] = [] 

    var body: some View {
        ZStack {
            // ── Game scene ───────────────────────────────────────────────────
            SpriteView(scene: sceneHolder.scene(for: state))
                .ignoresSafeArea()

            // ── HUD ───────────────────────────────────────────────────────────
            // Visible only while actively running. Hidden during any freeze:
            //   • isGameOver       → results take over
            //   • quizActive       → bonus-quiz panel
            //   • needsRefuel      → RefuelOverlay
            //   • preRunWarmup     → RefuelOverlay
            //   • isCountingDown   → CountdownOverlay
            if !state.isGameOver && !state.quizActive
                && !state.needsRefuel && !state.preRunWarmup
                && !state.isCountingDown {
                hudOverlay
            }

            // ── Countdown (top priority — runs AFTER refuel cycle ends) ───
            if state.isCountingDown {
                CountdownOverlayView(state: state)
                    .transition(.opacity)
            }

            // ── Refuel overlay (pre-run warmup OR mid-run refuel) ─────────
            // Both phases render the same panel; the header copy differs.
            if state.needsRefuel || state.preRunWarmup {
                RefuelOverlayView(
                    state: state,
                    onFail: { state.failRefuel() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Challenge overlay (mid-game bonus quiz) ────────────────────
            // Only shown when a bonus quiz is active AND we're not in the
            // refuel cycle (refuel path uses its own panel inside
            // RefuelOverlayView to route answers to submitRefuel).
            if state.quizActive && !state.needsRefuel && !state.preRunWarmup {
                challengeOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Results ───────────────────────────────────────────────────────
            if state.isGameOver {
                CapySurfersResultsView(
                    state: state,
                    onPlayAgain: { state.restartGame() },
                    onShop:      { showShop = true },
                    onMenu:      { dismiss() }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: state.isGameOver)
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: state.quizActive)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state.isCountingDown)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state.needsRefuel)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state.preRunWarmup)
        .sheet(isPresented: $showShop) { CapySurfersShopView(state: state) }
        // Phase 15 — pre-game gate. RefuelSessionView drives the +5s/-5s/0
        // delta and returns via onComplete; startRun() runs *after* the
        // gate so the capy's first frame already has a non-zero tank.
        .fullScreenCover(isPresented: $showPreGameGate) {
            RefuelSessionView(
                state: state,
                documents: documents,
                questionCount: 3,
                onComplete: {
                    state.completePreRunWarmup()
                    state.startRun()
                    showPreGameGate = false
                },
                allowDismiss: false
            )
        }
        .onAppear {
            state.loadQuestions(from: documents)
            // Phase 16 — read the persistent gate flag at mount. If the
            // user already completed the gate in a prior session, skip
            // the sheet and start the run immediately; otherwise fire it.
            showPreGameGate = !state.preGameGateSeen
            if !showPreGameGate {
                state.startRun()
            }
        }
        .onChange(of: state.isGameOver) { _, isOver in
            if isOver { commitEndRun() }
        }
        .interactiveDismissDisabled(true)
    }

    /// Hook end-of-run accounting into the project-wide XPManager + StreakManager,
    /// AND queue SM-2-lite mastery writeback through the Results view.
    private func commitEndRun() {
        state.endRun(xpManager: xpManager, streakManager: streakManager)
        // Per-item mastery writeback will be performed by CapySurfersResultsView
        // via @Query on StudyItem (it owns the typed ModelContext).
    }

    // MARK: - HUD

    private var hudOverlay: some View {
        VStack(spacing: 0) {
            // ── Top bar ───────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.40))
                        .clipShape(Circle())
                }

                Spacer()

                // Distance center
                VStack(spacing: 2) {
                    Text("\(state.distance)m")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    if state.distance > 0 && state.distance == state.highScore {
                        HStack(spacing: 4) {
                            TrophyIconView(size: 10, color: VerbaTheme.yellow)
                            Text("NEW BEST")
                                .font(VerbaFont.syne(.bold, size: 9))
                                .foregroundStyle(VerbaTheme.yellow)
                                .tracking(1.2)
                        }
                    }
                }

                Spacer()

                // Combo chip (NEW)
                ComboChipView(combo: state.combo, lastBoost: state.lastXPBoost)
                    .opacity(state.combo > 1 || state.lastXPBoost > 0 ? 1 : 0)

                Spacer().frame(width: 6)

                // Orbs (renamed visual hint, keep behavior)
                HStack(spacing: 4) {
                    CoinIconView(size: 15)
                    Text("\(state.melonsThisRun)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(VerbaTheme.yellow)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.32))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 52)

            // ── Focus bar ────────────────────────────────────────────────────
            energyBar
                .padding(.horizontal, 18)
                .padding(.top, 10)

            // ── Active powerup ────────────────────────────────────────────────
            if let pu = state.activePowerup {
                powerupBar(pu)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            // ── Swipe hints (first ~30m) ──────────────────────────────────────
            if state.distance < 30 {
                swipeHints.padding(.bottom, 44)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.activePowerup?.rawValue)
    }

    // MARK: - Energy Bar

    private var energyBar: some View {
        // Phase 15 — unit rebased to SECONDS. pct denominator is the
        // secondsCap factory constant so the bar always reads against
        // a 30-second full tank regardless of which constants Phase N
        // dialed in.
        let pct        = CGFloat(state.energy) / CGFloat(CapySurfersState.secondsCap)
        let barColor   = pct > 0.5 ? Color(red: 0.18, green: 0.82, blue: 0.45)
                       : pct > 0.25 ? VerbaTheme.orange
                       : VerbaTheme.danger
        let isLow      = state.energy < CapySurfersState.secondsCap * 0.25

        return HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isLow ? VerbaTheme.danger : .white)
                .scaleEffect(state.energyFlash ? 1.3 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: state.energyFlash)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * pct), height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pct)
                    if isLow {
                        Capsule()
                            .fill(VerbaTheme.danger.opacity(state.energyFlash ? 0.5 : 0))
                            .frame(width: geo.size.width * pct, height: 8)
                            .animation(.easeOut(duration: 0.35), value: state.energyFlash)
                    }
                }
            }
            .frame(height: 8)

            // Phase 15: '%' → 's' label so the HUD honestly reflects
            // what the field stores (seconds of tank remaining).
            Text("\(Int(state.energy))s")
                .font(VerbaFont.syne(.bold, size: 11))
                .foregroundStyle(isLow ? VerbaTheme.danger : .white.opacity(0.7))
                .frame(width: 34, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.black.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isLow ? VerbaTheme.danger.opacity(0.6) : .white.opacity(0.10), lineWidth: 1.5)
        )
    }

    // MARK: - Powerup Bar

    private func powerupBar(_ type: PowerupType) -> some View {
        HStack(spacing: 10) {
            PowerupIconView(type: type, size: 18, color: powerupColor(type))
            Text(type.label.uppercased())
                .font(VerbaFont.syne(.bold, size: 11))
                .foregroundStyle(.white)
                .tracking(0.8)
            Spacer()
            if type != .shield {
                let progress = state.powerupTimeLeft / type.duration
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.18)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(powerupColor(type))
                            .frame(width: geo.size.width * CGFloat(max(0, progress)), height: 5)
                            .animation(.linear(duration: 0.1), value: state.powerupTimeLeft)
                    }
                }
                .frame(width: 75, height: 5)
            } else {
                Image(systemName: "shield.fill").foregroundStyle(powerupColor(type)).font(.system(size: 13))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(powerupColor(type).opacity(0.5), lineWidth: 1.5))
    }

    // Phase 21: PowerupType extended from 4 to 8 cases (added headStart,
    // doubleCoins, timeFreeze, brainBoost). Every case must be present here
    // or Swift rejects the switch with "Switch must be exhaustive". Color
    // palette signals the power-up's effect category at a glance:
    //   • magnet / turbo / timeFreeze          → blue / teal / icy-blue   (motion)
    //   • shield / rocket                      → cyan / orange            (utility)
    //   • headStart / doubleCoins / brainBoost → green / gold / purple    (boosts)
    private func powerupColor(_ type: PowerupType) -> Color {
        switch type {
        case .magnet:      return Color(red: 0.40, green: 0.60, blue: 1.00)   // sky-blue    (attract)
        case .shield:      return Color(red: 0.20, green: 0.90, blue: 1.00)   // cyan        (defend)
        case .rocket:      return Color(red: 1.00, green: 0.45, blue: 0.20)   // orange      (thrust)
        case .turbo:       return Color(red: 0.20, green: 0.85, blue: 0.65)   // teal        (boost)
        // Phase 21 additions (must be present or switch fails to compile):
        case .headStart:   return Color(red: 0.30, green: 0.85, blue: 0.40)   // green       (energy)
        case .doubleCoins: return Color(red: 1.00, green: 0.80, blue: 0.20)   // gold        (currency)
        case .timeFreeze:  return Color(red: 0.65, green: 0.85, blue: 1.00)   // icy-blue    (slow)
        case .brainBoost:  return Color(red: 0.75, green: 0.40, blue: 0.95)   // purple      (xp)
        }
    }

    // MARK: - Swipe Hints

    private var swipeHints: some View {
        HStack(spacing: 0) {
            hint("←", "left"); Spacer()
            hint("↑", "jump"); Spacer()
            hint("↓", "duck"); Spacer()
            hint("→", "right")
        }
        .padding(.horizontal, 36).padding(.vertical, 11)
        .background(.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 24)
    }

    private func hint(_ arrow: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(arrow).font(.system(size: 19, weight: .black)).foregroundStyle(.white.opacity(0.65))
            Text(label).font(VerbaFont.syne(.medium, size: 9)).foregroundStyle(.white.opacity(0.38)).tracking(0.5)
        }
    }

    // MARK: - Challenge Overlay (6 kinds dispatch)

    private var challengeOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.72))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    challengeHeader

                    if let c = state.currentChallenge {
                        challengePanel(c)
                    } else {
                        // No question available — auto-resume
                        Color.clear.onAppear {
                            state.energy = min(100, state.energy + 40)
                            NotificationCenter.default.post(name: .capyResume, object: nil)
                            state.quizActive = false
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(red: 0.09, green: 0.09, blue: 0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(challengeBorderColor, lineWidth: 1.5)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
        }
    }

    private var challengeBorderColor: Color {
        if let correct = state.lastSubmitCorrect {
            return (correct ? VerbaTheme.green : VerbaTheme.danger).opacity(0.7)
        }
        return state.quizIsBonus
            ? VerbaTheme.yellow.opacity(0.6)
            : VerbaTheme.danger.opacity(0.6)
    }

    private var challengeHeader: some View {
        let kindLabel = state.currentChallenge?.kind.displayName ?? ""
        return HStack(spacing: 8) {
            Image(systemName: state.quizIsBonus ? "star.fill" : "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(state.quizIsBonus ? VerbaTheme.yellow : VerbaTheme.danger)
            Text(state.quizIsBonus ? "BONUS · \(kindLabel.uppercased())" : "\(kindLabel.uppercased()) · ENERGY BREAK")
                .font(VerbaFont.syne(.bold, size: 12))
                .foregroundStyle(.white)
                .tracking(1.2)
            Spacer()
            if state.quizIsBonus {
                Text("+focus").font(VerbaFont.syne(.bold, size: 11)).foregroundStyle(VerbaTheme.yellow)
            } else {
                Text("answer to continue").font(VerbaFont.syne(.regular, size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            state.quizIsBonus
                ? VerbaTheme.yellow.opacity(0.12)
                : VerbaTheme.danger.opacity(0.12)
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28))
    }

    @ViewBuilder
    private func challengePanel(_ c: StudyChallenge) -> some View {
        switch c.kind {
        case .multipleChoice(let options, let ci):
            mcqPanel(c: c, options: options, correctIndex: ci)
        case .trueFalse(let isTrue):
            trueFalsePanel(c: c, isTrue: isTrue)
        case .flashcardRecall(let answer):
            // Per-kind subview: its own @State for `revealed`. .id(c.id) forces
            // SwiftUI to instantiate a fresh struct on every challenge swap,
            // so the previous challenge's revealed/revealed-again state can
            // never leak into the new one.
            FlashcardPanelView(prompt: c.prompt,
                               answer: answer,
                               resolved: state.challengeResolved,
                               onSubmit: { state.submit($0) })
                .id(c.id)
        case .imageQuestion(let symbol, let options, let ci):
            imagePanel(c: c, symbol: symbol, options: options, correctIndex: ci)
        case .diagramID(let symbol, let options, let ci):
            imagePanel(c: c, symbol: symbol, options: options, correctIndex: ci, diagram: true)
        case .matchTheTerm:
            // Per-kind subview: owns shuffledDefs + selections + pickedTerm.
            // .id(c.id) gives each challenge a fresh instance, eliminating
            // the leak between challenges and removing the need for sync/async
            // re-shuffling. Replaces the implicit auto-submit with an explicit
            // "Submit Match" button gated by `canSubmit`.
            MatchPairsPanelView(prompt: c.prompt,
                                pairs: matchPairs(c),
                                resolved: state.challengeResolved,
                                correctMap: matchResultMap(c),
                                onSubmit: { state.submit($0) })
                .id(c.id)
        @unknown default:
            // Fallback for future challenge kinds: auto-resume the run.
            Color.clear.onAppear {
                state.energy = min(100, state.energy + 40)
                NotificationCenter.default.post(name: .capyResume, object: nil)
                state.quizActive = false
            }
        }
    }

    /// Extracts `[(String, String)]` from the current challenge's matchTheTerm kind.
    private func matchPairs(_ c: StudyChallenge) -> [(String, String)] {
        if case let .matchTheTerm(pairs) = c.kind { return pairs }
        return []
    }

    /// If the user already submitted a `.pairs` answer for *this* challenge,
    /// return [term: chosenDefinition]. Used by MatchPairsPanelView to paint
    /// each row green/red after submission so the user sees which pair was
    /// wrong. Returns an empty map when the challenge is unresolved.
    private func matchResultMap(_ c: StudyChallenge) -> [String: String] {
        guard state.challengeResolved,
              c.id == state.currentChallenge?.id,
              case let .pairs(map) = state.lastAnswer else { return [:] }
        return map
    }

    // ── Panel: MCQ (also used by imageQuestion / diagramID) ──────────────

    private func mcqPanel(c: StudyChallenge, options: [String], correctIndex: Int) -> some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 44)
                Text(c.prompt)
                    .font(VerbaFont.syne(.semibold, size: c.prompt.count > 100 ? 15 : 17))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 20)

            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    optionButton(label: options[i], index: i, correctIndex: correctIndex)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 22)
        }
    }

    // ── Panel: True/False ───────────────────────────────────────────────

    private func trueFalsePanel(c: StudyChallenge, isTrue: Bool) -> some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 44)
                Text(c.prompt)
                    .font(VerbaFont.syne(.semibold, size: 17))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 20)

            HStack(spacing: 12) {
                optionButtonBool(label: "True", value: true,   correct: isTrue, disabled: state.challengeResolved, fullWidth: false)
                optionButtonBool(label: "False", value: false, correct: isTrue, disabled: state.challengeResolved, fullWidth: false)
            }
            .padding(.horizontal, 16).padding(.bottom, 22)
        }
    }

    // ── Panel: Image Question / Diagram ID ──────────────────────────────

    private func imagePanel(c: StudyChallenge, symbol: String, options: [String], correctIndex: Int, diagram: Bool = false) -> some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(VerbaTheme.yellow)
                    .frame(width: 52, height: 52)
                    .background(VerbaTheme.yellow.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(c.prompt)
                    .font(VerbaFont.syne(.semibold, size: c.prompt.count > 80 ? 13 : 15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 20)

            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    optionButton(label: options[i], index: i, correctIndex: correctIndex)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 22)
        }
    }

    // ── Generic option buttons ─────────────────────────────────────────

    private func optionButton(label: String, index: Int, correctIndex: Int) -> some View {
        let answered = state.quizAnswered
        let isCorrect = index == correctIndex
        let isPicked  = answered == index

        let bg: Color = answered == nil
            ? Color.white.opacity(0.07)
            : isCorrect ? VerbaTheme.green.opacity(0.22)
            : isPicked  ? VerbaTheme.danger.opacity(0.20)
            : Color.white.opacity(0.04)
        let border: Color = answered == nil
            ? .white.opacity(0.12)
            : isCorrect ? VerbaTheme.green.opacity(0.7)
            : isPicked  ? VerbaTheme.danger.opacity(0.6)
            : .white.opacity(0.06)
        let textColor: Color = answered == nil
            ? .white
            : isCorrect ? VerbaTheme.green
            : isPicked  ? VerbaTheme.danger
            : .white.opacity(0.35)

        return Button {
            guard answered == nil else { return }
            HapticManager.impact(.light)
            state.submit(.index(index))
        } label: {
            HStack(spacing: 12) {
                Text(["A","B","C","D"][index])
                    .font(VerbaFont.syne(.bold, size: 12))
                    .foregroundStyle(answered == nil ? .white.opacity(0.45) : textColor.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(border.opacity(0.3))
                    .clipShape(Circle())
                Text(label)
                    .font(VerbaFont.syne(.medium, size: 14))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Spacer()
                if answered != nil {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(VerbaTheme.green).font(.system(size: 16))
                    } else if isPicked {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(VerbaTheme.danger).font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(answered != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: state.challengeResolved)
    }

    private func optionButtonBool(label: String, value: Bool, correct: Bool, disabled: Bool, fullWidth: Bool) -> some View {
        // Derive post-submit feedback directly from `state.lastAnswer`. The
        // computed `state.quizAnswered` only handles `.index(Int)` challenges
        // and returns nil for `.bool`, so reading through it would always
        // look un-answered here even after the user picked True/False.
        let lastValue: Bool? = {
            if case let .bool(b) = state.lastAnswer { return b }
            return nil
        }()
        let userPicked = lastValue != nil
        let isCorrectPick = userPicked && value == correct
        let isWrongPick   = userPicked && value != correct

        let bg = !userPicked ? Color.white.opacity(0.07)
                : isCorrectPick ? VerbaTheme.green.opacity(0.22)
                : VerbaTheme.danger.opacity(0.18)
        let border = !userPicked ? .white.opacity(0.12)
                     : isCorrectPick ? VerbaTheme.green.opacity(0.7)
                     : VerbaTheme.danger.opacity(0.6)
        let tint = !userPicked ? .white
                   : isCorrectPick ? VerbaTheme.green
                   : isWrongPick ? VerbaTheme.danger : .white

        return Button {
            guard !disabled else { return }
            HapticManager.impact(.light)
            state.submit(.bool(value))
        } label: {
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                if isCorrectPick { Image(systemName: "checkmark.circle.fill").foregroundStyle(VerbaTheme.green) }
                else if isWrongPick { Image(systemName: "xmark.circle.fill").foregroundStyle(VerbaTheme.danger) }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 16).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - ComboChipView

struct ComboChipView: View {
    let combo: Int
    let lastBoost: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
            Text("x\(combo)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(
            combo >= 5 ? VerbaTheme.yellow
            : combo >= 3 ? Color(red: 0.95, green: 0.55, blue: 0.10)
            : VerbaTheme.green
        )
        .clipShape(Capsule())
        .scaleEffect(combo >= 3 ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: combo)
        .overlay(
            Capsule().stroke(.white.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - FlashcardPanelView
//
// Per-kind subview that owns its `@State revealed` Bool. The parent attaches
// `.id(c.id)` so SwiftUI discards this entire struct on every challenge swap,
// guaranteeing the previous challenge's reveal state cannot leak.

private struct FlashcardPanelView: View {
    let prompt:   String
    let answer:   String
    let resolved: Bool
    let onSubmit: (StudyChallenge.Answer) -> Void

    @State private var revealed: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 44)
                Text(prompt)
                    .font(VerbaFont.syne(.semibold, size: 18))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 20)

            if revealed || resolved {
                VStack(spacing: 8) {
                    Text("answer")
                        .font(VerbaFont.syne(.bold, size: 10))
                        .foregroundStyle(VerbaTheme.green)
                        .tracking(1.5)
                    Text(answer)
                        .font(VerbaFont.syne(.semibold, size: 20))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)

                if !resolved {
                    Button {
                        HapticManager.success()
                        revealed = false
                        onSubmit(.revealed)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("i remembered")
                        }
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(VerbaTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }
            } else {
                Button {
                    HapticManager.light()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        revealed = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                        Text("reveal answer")
                    }
                    .font(VerbaFont.syne(.bold, size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.20), lineWidth: 1))
                }
                .padding(.horizontal, 16).padding(.bottom, 22)
            }
        }
    }
}

// MARK: - MatchPairsPanelView
//
// Per-kind subview with its own @State for termSelected / selections /
// shuffledDefs. The parent attaches `.id(c.id)` so SwiftUI discards the
// struct between challenges — no body-side-effect shimmer, no onAppear /
// onChange reset dances, no state leak between kinds.
//
// Replaces the legacy "auto-submit on every def-tap" with an explicit Submit
// Match button that's gated by `canSubmit` (all terms chosen + not resolved).
// Per-row tint continues to use a post-submit `correctMap` so the user sees
// green for correct pairs and red for incorrect ones during the 1.1s feedback
// window.

private struct MatchPairsPanelView: View {
    let prompt:    String
    let pairs:     [(String, String)]            // [(term, definition)]
    let resolved:  Bool
    let correctMap: [String: String]             // term → chosenDefinition (only populated after submit)
    let onSubmit:  (StudyChallenge.Answer) -> Void

    @State private var termSelected: String? = nil
    @State private var selections: [String: String] = [:]
    @State private var shuffledDefs: [String]

    init(prompt: String,
         pairs: [(String, String)],
         resolved: Bool,
         correctMap: [String: String],
         onSubmit: @escaping (StudyChallenge.Answer) -> Void) {
        self.prompt      = prompt
        self.pairs       = pairs
        self.resolved    = resolved
        self.correctMap  = correctMap
        self.onSubmit    = onSubmit
        // Shuffle exactly once per view-identity. Because the parent attaches
        // `.id(c.id)`, this struct is re-instantiated on every challenge
        // transition, so each new challenge gets a fresh shuffle with no
        // body-side-effect.
        self._shuffledDefs = State(initialValue: pairs.map(\.1).shuffled())
    }

    // `pairs.isEmpty` is a defensive guard — state.buildChallenge currently
    // only emits matchTheTerm when the question pool has real StudyItems, so
    // this is unreachable on first-party data. Future flows that funnel
    // matchTheTerm with an empty pairs array must not unlock Submit against
    // no rows.
    private var canSubmit: Bool {
        !pairs.isEmpty && selections.count == pairs.count && !resolved
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 40)
                Text(prompt)
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 16)

            VStack(spacing: 8) {
                ForEach(pairs.indices, id: \.self) { i in
                    let term    = pairs[i].0
                    let pairDef = pairs[i].1
                    let chosenDef = selections[term]
                    let submittedDef = correctMap[term]

                    HStack(spacing: 10) {
                        // Term chip (tappable to pick an active term)
                        Button { HapticManager.light(); termSelected = term } label: {
                            Text(term)
                                .font(VerbaFont.syne(.semibold, size: 13))
                                .foregroundStyle(termSelected == term ? .black : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(termSelected == term ? VerbaTheme.green : .white.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(resolved)

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.white.opacity(0.4))
                            .font(.system(size: 11))

                        // Definition chip (tappable to assign shown def to active term)
                        Button { assignDefinitionAt(i) } label: {
                            Text(shuffledDefs.indices.contains(i) ? shuffledDefs[i] : pairDef)
                                .font(VerbaFont.syne(.medium, size: 12))
                                .foregroundStyle(rowTint(chosenDef: chosenDef,
                                                          submittedDef: submittedDef,
                                                          pairDef: pairDef))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(resolved || termSelected == nil)
                    }
                }
            }
            .padding(.horizontal, 16)

            // Explicit Submit Match — replaces the prior auto-submit-on-tap.
            Button {
                guard canSubmit else { return }
                HapticManager.success()
                onSubmit(.pairs(selections))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("submit match")
                }
                .font(VerbaFont.syne(.bold, size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(canSubmit ? VerbaTheme.green : .white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canSubmit)
            .padding(.horizontal, 16).padding(.bottom, 22)
        }
    }

    // ── Per-row tint logic ────────────────────────────────────────────

    /// Color the row according to (in priority order):
    ///   1. After submit, paint green when chosen == pair def, red otherwise.
    ///   2. While in-progress, paint bright when the user has chosen a def for the term.
    private func rowTint(chosenDef: String?,
                         submittedDef: String?,
                         pairDef: String) -> Color {
        if resolved {
            guard let submitted = submittedDef else { return .white.opacity(0.5) }
            return submitted == pairDef ? VerbaTheme.green : VerbaTheme.danger
        }
        return chosenDef != nil ? VerbaTheme.yellow : .white
    }

    private func assignDefinitionAt(_ i: Int) {
        guard let term = termSelected else { return }
        let def = shuffledDefs.indices.contains(i) ? shuffledDefs[i] : pairs[i].1
        selections[term] = def
        // Active term auto-deselects after assignment so the next tap reads naturally.
        termSelected = nil
        HapticManager.light()
    }
}

// MARK: - SceneHolder

private final class SceneHolder {
    // Phase 16 — SceneHolder now routes to CapyTrainScene, the
    // pastel train-track SKScene that replaces the original
    // CapySurfersScene. SpriteView(scene:) accepts any SKScene so
    // the call site doesn't change. The original CapySurfersScene
    // file remains on disk as dead code pending a cleanup sweep.
    private var _scene: CapyTrainScene?

    func scene(for state: CapySurfersState) -> CapyTrainScene {
        if let s = _scene { return s }
        let s = CapyTrainScene(state: state)
        s.size      = UIScreen.main.bounds.size
        s.scaleMode = .resizeFill
        _scene = s
        return s
    }
}

// MARK: - RefuelOverlayView
//
// Phase 5: shown when the player needs to answer 3 flashcard questions to
// refill Capy's juice — either as a pre-run warmup (state.preRunWarmup == true)
// or as a mid-run freeze (state.needsRefuel == true). Both phases render the
// same panel; only the header copy differs.
//
// State machine contract (driven by CapySurfersState):
//   • submitRefuel(_:)  — called when the player picks an answer; flips
//     `challengeResolved` and increments `refuelProgress` on a correct hit.
//   • When `refuelProgress` hits `refuelTarget` (3), we call `beginCountdown()`,
//     which flips `isCountingDown` true. CountdownOverlayView takes over from
//     there.
//   • 1.1s after `challengeResolved` becomes true, we serve the next refuel
//     question via `serveNextRefuelQuestion()` — unless the cycle is complete.
//
// Visual identity:
//   • Moss-green header (VerbaTheme.sage), matching the master prompt's
//     "matcha & moss" brief.
//   • Snail mascot in the header — secondary brand identity, complements
//     CapybaraDrawing on the warmup screen.
//   • Progress chip on the right side: 3 dots fill from amber as the player
//     answers correctly.
//
private struct RefuelOverlayView: View {
    @ObservedObject var state: CapySurfersState
    let onFail: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.72))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    refuelHeader

                    if let c = state.currentChallenge {
                        refuelPanel(c)
                            .id(c.id)
                    } else {
                        // No question yet — feed the first one as soon as the
                        // overlay mounts. The 250ms delay lets the slide-up
                        // animation complete before the panel content swaps.
                        // Note: we ALSO need the `currentChallenge == nil`
                        // guard, because the outer RefuelOverlayView.onAppear
                        // below may have already served Q1 by the time this
                        // scheduled block fires. Without the nil-check, a
                        // freshly-served question would be overwritten ~250ms
                        // later with Q2 — a visible flash / answered-no-answer
                        // race. (Discovered by code review.)
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    if (state.needsRefuel || state.preRunWarmup)
                                        && state.currentChallenge == nil {
                                        state.serveNextRefuelQuestion()
                                    }
                                }
                            }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(red: 0.09, green: 0.13, blue: 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(VerbaTheme.sage.opacity(0.55), lineWidth: 1.5)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
        }
        .onChange(of: state.refuelProgress) { _, newValue in
            if newValue >= state.refuelTarget {
                // Refuel cycle complete — start the 3-2-1 countdown.
                // The CountdownOverlayView in CapySurfersGameView takes over
                // here. After 3 seconds it calls either commitRefuel()
                // (mid-run) or completePreRunWarmup() (pre-run).
                state.beginCountdown()
            }
        }
        .onChange(of: state.challengeResolved) { _, resolved in
            // After the 1.1s feedback window, serve the next refuel question
            // UNLESS the cycle is complete (in which case beginCountdown()
            // already fired from the refuelProgress observer above).
            if resolved {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    if (state.needsRefuel || state.preRunWarmup)
                        && state.refuelProgress < state.refuelTarget {
                        state.serveNextRefuelQuestion()
                    }
                }
            }
        }
        .onAppear {
            // Make sure the very first question is served when the overlay
            // mounts (e.g. on pre-run warmup).
            if (state.needsRefuel || state.preRunWarmup)
                && state.currentChallenge == nil {
                state.serveNextRefuelQuestion()
            }
        }
    }

    // MARK: - Header

    private var refuelHeader: some View {
        HStack(spacing: 10) {
            SnailMascot(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.preRunWarmup ? "warm up!" : "out of juice!")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(state.preRunWarmup
                     ? "answer 3 to fuel capy and start the run"
                     : "answer 3 correctly to refuel and keep your run alive")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            refuelProgressChip
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [VerbaTheme.sage.opacity(0.55), VerbaTheme.darkOliveInk.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28))
    }

    private var refuelProgressChip: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, state.refuelTarget), id: \.self) { i in
                Circle()
                    .fill(i < state.refuelProgress ? VerbaTheme.amber : Color.white.opacity(0.22))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(VerbaTheme.amber.opacity(i < state.refuelProgress ? 0.85 : 0), lineWidth: 1.5)
                    )
                    .scaleEffect(i < state.refuelProgress ? 1.10 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: state.refuelProgress)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    // MARK: - Panel dispatch (submits via submitRefuel, NOT submit)

    @ViewBuilder
    private func refuelPanel(_ c: StudyChallenge) -> some View {
        switch c.kind {
        case .multipleChoice(let options, let ci):
            refuelMCQ(c: c, options: options, correctIndex: ci)
        case .trueFalse(let isTrue):
            refuelTrueFalse(c: c, isTrue: isTrue)
        case .flashcardRecall(let answer):
            refuelFlashcard(c: c, answer: answer)
        case .imageQuestion(let symbol, let options, let ci):
            refuelImage(c: c, symbol: symbol, options: options, correctIndex: ci)
        case .diagramID(let symbol, let options, let ci):
            refuelImage(c: c, symbol: symbol, options: options, correctIndex: ci)
        case .matchTheTerm:
            refuelMCQ(c: c,
                      options: matchPairs(c).map(\.1).shuffled().prefix(4).map { String($0.prefix(60)) } + [c.prompt],
                      correctIndex: 0)
        @unknown default:
            // Fallback for future challenge kinds during refuel: no-op panel.
            VStack(spacing: 18) {
                Text("Unsupported question type")
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .foregroundStyle(.white)
                    .padding(.vertical, 24)
                Button {
                    // Treat as incorrect to allow user to continue to next question
                    HapticManager.impact(.light)
                    state.submitRefuel(.revealed)
                } label: {
                    Text("continue")
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func matchPairs(_ c: StudyChallenge) -> [(String, String)] {
        if case let .matchTheTerm(pairs) = c.kind { return pairs }
        return []
    }

    private func refuelMCQ(c: StudyChallenge, options: [String], correctIndex: Int) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 42)
                Text(c.prompt)
                    .font(VerbaFont.syne(.semibold, size: c.prompt.count > 100 ? 14 : 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 18)

            VStack(spacing: 9) {
                ForEach(options.indices, id: \.self) { i in
                    refuelOptionButton(label: options[i], index: i, correctIndex: correctIndex)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
    }

    private func refuelTrueFalse(c: StudyChallenge, isTrue: Bool) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 42)
                Text(c.prompt)
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 18)

            HStack(spacing: 12) {
                refuelOptionButtonBool(label: "True",  value: true,  correct: isTrue)
                refuelOptionButtonBool(label: "False", value: false, correct: isTrue)
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
    }

    private func refuelFlashcard(c: StudyChallenge, answer: String) -> some View {
        RefuelFlashcardPanel(
            prompt: c.prompt,
            answer: answer,
            resolved: state.challengeResolved,
            onSubmit: { state.submitRefuel($0) }
        )
    }

    private func refuelImage(c: StudyChallenge, symbol: String, options: [String], correctIndex: Int) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 36))
                    .foregroundStyle(VerbaTheme.amber)
                    .frame(width: 48, height: 48)
                    .background(VerbaTheme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(c.prompt)
                    .font(VerbaFont.syne(.semibold, size: c.prompt.count > 80 ? 12 : 14))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 18)

            VStack(spacing: 9) {
                ForEach(options.indices, id: \.self) { i in
                    refuelOptionButton(label: options[i], index: i, correctIndex: correctIndex)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
    }

    // ── Option buttons (route to submitRefuel) ───────────────────────

    private func refuelOptionButton(label: String, index: Int, correctIndex: Int) -> some View {
        let answered = refuelPickedIndex()
        let isCorrect = index == correctIndex
        let isPicked  = answered == index

        let bg: Color = answered == nil
            ? Color.white.opacity(0.07)
            : isCorrect ? VerbaTheme.green.opacity(0.22)
            : isPicked  ? VerbaTheme.danger.opacity(0.20)
            : Color.white.opacity(0.04)
        let border: Color = answered == nil
            ? Color.white.opacity(0.12)
            : isCorrect ? VerbaTheme.green.opacity(0.7)
            : isPicked  ? VerbaTheme.danger.opacity(0.6)
            : Color.white.opacity(0.06)
        let textColor: Color = answered == nil
            ? .white
            : isCorrect ? VerbaTheme.green
            : isPicked  ? VerbaTheme.danger
            : Color.white.opacity(0.35)

        return Button {
            guard answered == nil else { return }
            HapticManager.impact(.light)
            state.submitRefuel(.index(index))
        } label: {
            HStack(spacing: 12) {
                Text(["A","B","C","D"][index])
                    .font(VerbaFont.syne(.bold, size: 12))
                    .foregroundStyle(answered == nil ? Color.white.opacity(0.45) : textColor.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(border.opacity(0.3))
                    .clipShape(Circle())
                Text(label)
                    .font(VerbaFont.syne(.medium, size: 14))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Spacer()
                if answered != nil {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(VerbaTheme.green).font(.system(size: 16))
                    } else if isPicked {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(VerbaTheme.danger).font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(answered != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: state.challengeResolved)
    }

    private func refuelOptionButtonBool(label: String, value: Bool, correct: Bool) -> some View {
        let lastValue: Bool? = {
            if case let .bool(b) = state.lastAnswer { return b }
            return nil
        }()
        let userPicked = lastValue != nil
        let isCorrectPick = userPicked && value == correct
        let isWrongPick   = userPicked && value != correct

        let bg = !userPicked ? Color.white.opacity(0.07)
                : isCorrectPick ? VerbaTheme.green.opacity(0.22)
                : VerbaTheme.danger.opacity(0.18)
        let border = !userPicked ? Color.white.opacity(0.12)
                     : isCorrectPick ? VerbaTheme.green.opacity(0.7)
                     : VerbaTheme.danger.opacity(0.6)
        let tint = !userPicked ? Color.white
                   : isCorrectPick ? VerbaTheme.green
                   : isWrongPick ? VerbaTheme.danger : Color.white

        return Button {
            guard !state.challengeResolved else { return }
            HapticManager.impact(.light)
            state.submitRefuel(.bool(value))
        } label: {
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                if isCorrectPick { Image(systemName: "checkmark.circle.fill").foregroundStyle(VerbaTheme.green) }
                else if isWrongPick { Image(systemName: "xmark.circle.fill").foregroundStyle(VerbaTheme.danger) }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(state.challengeResolved)
    }

    // MARK: - Refuel-mode lastAnswer index extraction

    private func refuelPickedIndex() -> Int? {
        guard state.challengeResolved,
              state.currentChallenge?.id != nil else { return nil }
        if case let .index(i) = state.lastAnswer { return i }
        return nil
    }
}

// MARK: - RefuelFlashcardPanel
//
// Per-kind subview for the flashcard refuel variant. Mirrors FlashcardPanelView
// but routes the answer through `submitRefuel`. Owns its `@State revealed` so
// each new challenge (parent attaches .id(c.id)) gets a fresh instance.

private struct RefuelFlashcardPanel: View {
    let prompt:   String
    let answer:   String
    let resolved: Bool
    let onSubmit: (StudyChallenge.Answer) -> Void

    @State private var revealed: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VerbaMascot(mood: .thinking, size: 42)
                Text(prompt)
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 18)

            if revealed || resolved {
                VStack(spacing: 6) {
                    Text("answer")
                        .font(VerbaFont.syne(.bold, size: 10))
                        .foregroundStyle(VerbaTheme.green)
                        .tracking(1.5)
                    Text(answer)
                        .font(VerbaFont.syne(.semibold, size: 18))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)

                if !resolved {
                    Button {
                        HapticManager.success()
                        revealed = false
                        onSubmit(.revealed)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("i remembered")
                        }
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(VerbaTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 16).padding(.top, 6)
                }
            } else {
                Button {
                    HapticManager.light()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        revealed = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                        Text("reveal answer")
                    }
                    .font(VerbaFont.syne(.bold, size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 1))
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
    }
}

// MARK: - CountdownOverlayView
//
// Phase 5: 3-2-1-GO countdown that fires after a successful refuel cycle.
// Drives the timing internally via Task.sleep so state stays pure (no Timer
// inside CapySurfersState). When countdownStep reaches 3 ("GO!"), commits
// the refuel — either commitRefuel() (mid-run) or completePreRunWarmup()
// (pre-run warmup), depending on which phase the player is in.

private struct CountdownOverlayView: View {
    @ObservedObject var state: CapySurfersState
    @State private var didCommit = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(headlineText)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(1.2)
                    .textCase(.uppercase)

                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 200, height: 200)
                    Circle()
                        .stroke(VerbaTheme.amber.opacity(0.85), lineWidth: 4)
                        .frame(width: 200, height: 200)
                    Text(displayText)
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(stepColor)
                        .shadow(color: stepColor.opacity(0.65), radius: 12, x: 0, y: 0)
                        .scaleEffect(scale)
                        .id("step-\(state.countdownStep)")
                        .transition(.scale.combined(with: .opacity))
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.65), value: state.countdownStep)

                Text(trailingText)
                    .font(VerbaFont.syne(.medium, size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            await runCountdown()
        }
    }

    private var displayText: String {
        switch state.countdownStep {
        case 0:    return "3"
        case 1:    return "2"
        case 2:    return "1"
        default:   return "GO!"
        }
    }

    private var stepColor: Color {
        switch state.countdownStep {
        case 0:    return VerbaTheme.amber
        case 1:    return VerbaTheme.amber
        case 2:    return VerbaTheme.amber
        default:   return VerbaTheme.green
        }
    }

    private var scale: CGFloat {
        state.countdownStep >= 3 ? 1.20 : 1.0
    }

    private var headlineText: String {
        state.preRunWarmup ? "ready?" : "refueled!"
    }

    private var trailingText: String {
        state.preRunWarmup
            ? "get ready to run"
            : "back to surfing — keep it alive"
    }

    private func runCountdown() async {
        guard !didCommit else { return }
        didCommit = true

        // 4 ticks: "3" → "2" → "1" → "GO!"
        for step in 0...3 {
            // Step pulse already animated by SwiftUI via state.countdownStep.
            try? await Task.sleep(for: .milliseconds(900))
            if Task.isCancelled { return }
            state.countdownStep = step + 1
        }

        // Hold "GO!" briefly so the player registers it.
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }

        // Commit phase: pre-run warmup → completePreRunWarmup(), mid-run → commitRefuel().
        if state.preRunWarmup {
            state.completePreRunWarmup()
        } else {
            state.commitRefuel()
        }
        didCommit = false   // reset for next cycle
    }
}
