import SwiftUI
import SpriteKit

// MARK: - VerbaFlowGameView
// SwiftUI wrapper around the SpriteKit scene + question overlay

struct VerbaFlowGameView: View {
    let document: Document?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var gameState = VerbaFlowState()
    @State private var scene: VerbaFlowScene? = nil

    var body: some View {
        ZStack {
            // ── Game ───────────────────────────────────────────────────────
            if let scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea()
            }

            // ── HUD ────────────────────────────────────────────────────────
            if !gameState.isGameOver && !gameState.showQuestion {
                hud
            }

            // ── Question overlay ───────────────────────────────────────────
            if gameState.showQuestion, let q = gameState.currentQuestion {
                questionOverlay(q)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
            }

            // ── Game over ──────────────────────────────────────────────────
            if gameState.isGameOver {
                gameOverOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            let s = VerbaFlowScene(state: gameState, document: document)
            s.size = UIScreen.main.bounds.size
            s.scaleMode = .resizeFill
            scene = s
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: gameState.showQuestion)
        .animation(.easeInOut(duration: 0.3), value: gameState.isGameOver)
    }

    // MARK: - HUD

    private var hud: some View {
        VStack {
            HStack {
                // Close
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(9)
                        .background(.black.opacity(0.3))
                        .clipShape(Circle())
                }

                Spacer()

                // Score
                VStack(spacing: 1) {
                    Text("\(gameState.score)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("score")
                        .font(VerbaFont.syne(.medium, size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                }

                Spacer()

                // Lives
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Image(systemName: i < gameState.lives ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                            .foregroundStyle(i < gameState.lives ? Color.red : Color.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)

            Spacer()

            // Swipe hint (fades after first 3 seconds)
            if gameState.score < 10 {
                HStack(spacing: 16) {
                    swipeHint("←", "left")
                    swipeHint("↑", "jump")
                    swipeHint("→", "right")
                }
                .padding(.bottom, 32)
            }
        }
    }

    private func swipeHint(_ arrow: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(arrow)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Text(label)
                .font(VerbaFont.syne(.medium, size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Question Overlay

    private func questionOverlay(_ q: FlowQuestion) -> some View {
        ZStack {
            // Blurred dark bg
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .background(VerbaTheme.cozySage.opacity(0.85))

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    // Barrier icon
                    ZStack {
                        Circle()
                            .fill(VerbaTheme.orange.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(VerbaTheme.orange)
                    }

                    // Question
                    VStack(spacing: 10) {
                        if !q.topic.isEmpty {
                            Text(q.topic.uppercased())
                                .font(VerbaFont.syne(.bold, size: 10))
                                .foregroundStyle(VerbaTheme.green)
                                .tracking(1.5)
                        }
                        Text(q.question)
                            .font(VerbaFont.syne(.semibold, size: 20))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)

                    // Options or free response
                    if q.isMCQ {
                        mcqOptions(q)
                    } else {
                        freeResponseInput(q)
                    }
                }
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func mcqOptions(_ q: FlowQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                Button {
                    let correct = i == q.correctIndex
                    gameState.answerQuestion(correct: correct)
                    HapticManager.impact(correct ? .light : .medium)
                } label: {
                    HStack(spacing: 12) {
                        Text(["A","B","C","D"][i % 4])
                            .font(VerbaFont.syne(.bold, size: 12))
                            .foregroundStyle(VerbaTheme.green)
                            .frame(width: 26, height: 26)
                            .background(VerbaTheme.green.opacity(0.15))
                            .clipShape(Circle())

                        Text(opt)
                            .font(VerbaFont.syne(.medium, size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func freeResponseInput(_ q: FlowQuestion) -> some View {
        VStack(spacing: 12) {
            TextField("type your answer…", text: $gameState.freeResponseText)
                .font(VerbaFont.syne(.regular, size: 15))
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VerbaTheme.green.opacity(0.4), lineWidth: 1)
                )
                .autocorrectionDisabled()

            Button {
                // Fuzzy match: if answer contains any key word from correct answer
                let typed   = gameState.freeResponseText.lowercased().trimmingCharacters(in: .whitespaces)
                let correct = q.options[q.correctIndex].lowercased()
                let words   = correct.components(separatedBy: " ").filter { $0.count > 3 }
                let isRight = words.contains { typed.contains($0) } || typed == correct
                gameState.freeResponseText = ""
                gameState.answerQuestion(correct: isRight)
                HapticManager.impact(isRight ? .light : .medium)
            } label: {
                Text("submit →")
                    .font(VerbaFont.syne(.bold, size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(VerbaTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(gameState.freeResponseText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Game Over

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                VerbaMascot(mood: .calm, size: 64)

                VStack(spacing: 8) {
                    Text("wiped out.")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("\(gameState.score) points · \(gameState.correctAnswers) questions correct")
                        .font(VerbaFont.syne(.medium, size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Stats
                HStack(spacing: 12) {
                    flowStat(value: "\(gameState.score)",           label: "score",    color: VerbaTheme.green)
                    flowStat(value: "\(gameState.correctAnswers)",  label: "correct",  color: VerbaTheme.orange)
                    flowStat(value: "\(gameState.barriers)",        label: "barriers", color: Color(red: 0.5, green: 0.4, blue: 1.0))
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button {
                        gameState.restart()
                    } label: {
                        Text("play again")
                            .font(VerbaFont.syne(.bold, size: 17))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(VerbaTheme.green)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: VerbaTheme.green.opacity(0.4), radius: 12, x: 0, y: 6)
                    }

                    Button("exit") { dismiss() }
                        .font(VerbaFont.syne(.medium, size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func flowStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
