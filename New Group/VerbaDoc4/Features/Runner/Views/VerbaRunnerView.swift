import SwiftUI
import SpriteKit
import SwiftData

// MARK: - VerbaRunnerView
//
// Full-screen game view. Owns RunSessionManager (and therefore GameScene).
// Presented as a .fullScreenCover from RunLobbyView.
//
// Layout: SpriteKit fills the entire screen; all UI layers are SwiftUI
// overlays drawn on top via ZStack. Gestures are handled here and forwarded
// to the scene so SwiftUI owns the gesture recogniser (more reliable than
// UISwipeGestureRecognizer added to SKView).
//
// XP / streak / Game Center are handled here (not in RunSessionManager) so
// the game engine stays free of environment object dependencies.

struct VerbaRunnerView: View {

    // MARK: - State

    @StateObject private var session = RunSessionManager()
    @Environment(\.dismiss)           private var dismiss
    @Environment(\.modelContext)      private var modelContext
    @Environment(\.scenePhase)        private var scenePhase

    @EnvironmentObject private var xpManager:    XPManager
    @EnvironmentObject private var streakManager: StreakManager

    // Load all non-orphan study items for the SRS gate system.
    @Query(
        filter: #Predicate<StudyItem> { $0.cardLayer != "orphan" },
        sort: [SortDescriptor(\StudyItem.mastery), SortDescriptor(\StudyItem.nextReviewAt)]
    )
    private var allItems: [StudyItem]

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── SpriteKit canvas ───────────────────────────────────────────
            SpriteView(scene: session.scene)
                .ignoresSafeArea()
                .gesture(swipeGesture)

            // ── State-driven overlays ──────────────────────────────────────
            switch session.state {
            case .lobby:
                EmptyView()

            case .countdown(let n):
                CountdownOverlay(count: n)
                    .transition(.opacity)
                    .allowsHitTesting(false)

            case .running:
                ZStack {
                    RunHUD(session: session) {
                        session.exitToLobby()
                        dismiss()
                    }
                    .transition(.opacity)

                    // Gate overlay appears on top of HUD when active
                    if let card = session.activeGateCard {
                        QuestionOverlayView(card: card, choices: session.activeGateChoices) { correct in
                            session.submitGateAnswer(correct: correct)
                            if correct { xpManager.award(.gateAnswerCorrect) }
                        }
                        .transition(.opacity)
                        .zIndex(50)
                    }
                }

            case .complete(let result):
                RunResultsView(result: result, onReplay: {
                    session.replay()
                }, onExit: {
                    dismiss()
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.state)
        .onAppear {
            // Inject items + save closure before the countdown starts.
            session.setStudyItems(allItems) { [modelContext] in
                try? modelContext.save()
            }
            // Forward per-gate XP to the onGateAnswered callback.
            // (Individual gate XP is awarded in the ZStack above; this
            //  block is reserved for future aggregate gate bonuses.)
            session.onGateAnswered = { _ in }
            session.startCountdown()
        }
        .onChange(of: session.state) { _, newState in
            if case .complete(let result) = newState {
                handleRunComplete(result)
            }
        }
        .onDisappear { session.exitToLobby() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, case .running = session.state {
                session.exitToLobby()
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Post-run rewards

    private func handleRunComplete(_ result: RunResult) {
        // Base XP for finishing a run
        xpManager.award(.runCompleted)

        // Perfect run bonus: all gates answered correctly (≥1 gate required)
        if result.gatesAnswered > 0 && result.gatesCorrect == result.gatesAnswered {
            xpManager.award(.perfectRun)
        }

        // Streak — runner counts as a study session for streak purposes
        streakManager.recordStudySession()

        // Session record (cardsReviewed = gates answered in runner context)
        let studySession = StudySession(
            date:          Date(),
            cardsReviewed: result.gatesAnswered,
            correctCount:  result.gatesCorrect,
            duration:      result.duration
        )
        SessionTracker.shared.record(session: studySession)
        // Note: Game Center score is submitted automatically by XPManager.award()
        // above — no explicit submitScore call needed here.
    }

    // MARK: - Swipe gesture (forwarded to scene)

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                // Block swipes while a gate overlay is showing
                guard session.activeGateCard == nil else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                // Only left/right — the capybara runs on flat ground (no jumping or sliding)
                guard abs(dx) > abs(dy) else { return }
                if dx > 0 { session.scene.handleSwipeRight() }
                else       { session.scene.handleSwipeLeft()  }
            }
    }
}

// MARK: - Countdown overlay

private struct CountdownOverlay: View {
    let count: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            Text("\(count)")
                .font(VerbaFont.serif(size: 96))
                .foregroundStyle(.white)
                .id(count)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
                .animation(.easeOut(duration: 0.35), value: count)
        }
    }
}

// MARK: - HUD (shown while running)

private struct RunHUD: View {
    @ObservedObject var session: RunSessionManager
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar ───────────────────────────────────────────────────
            HStack(alignment: .center) {
                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.80))
                        .padding(10)
                        .background(.black.opacity(0.30))
                        .clipShape(Circle())
                }

                Spacer()

                VStack(spacing: 1) {
                    Text("\(session.distance) m")
                        .font(VerbaFont.syne(.bold, size: 22))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("distance")
                        .font(VerbaFont.syne(.regular, size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                VStack(spacing: 1) {
                    Text("\(session.score)")
                        .font(VerbaFont.syne(.bold, size: 22))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("score")
                        .font(VerbaFont.syne(.regular, size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )

            Spacer()

            // ── Multiplier badge (bottom centre) ─────────────────────────
            if session.multiplier > 1.0 {
                Text("\(String(format: "%.1f", session.multiplier))×")
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(VerbaTheme.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(VerbaTheme.green.opacity(0.18))
                    .clipShape(Capsule())
                    .padding(.bottom, 50)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.20), value: session.multiplier)
            }
        }
    }
}
