import SwiftUI

// MARK: - RunLobbyView
//
// The entry point for VerbaFlow Runner — shown in the "Drill" tab.
// Shows personal bests and a start button.
// Presents VerbaRunnerView as a full-screen cover so the tab bar is hidden
// during gameplay.

struct RunLobbyView: View {

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var showRunner = false
    @AppStorage("runner.questionMode") private var questionMode = QuestionMode.multipleChoice

    // Personal bests read directly from UserDefaults; update on appear.
    @State private var bestScore:    Int = 0
    @State private var bestDistance: Int = 0

    private let bestScoreKey    = "runner.best.score"
    private let bestDistanceKey = "runner.best.distance"

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        Spacer(minLength: 20)

                        // ── Hero text ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("verbaflow\nrunner.")
                                .font(VerbaFont.serif(size: 34))
                                .foregroundStyle(VerbaTheme.ink)
                                .lineSpacing(2)
                            Text("dodge obstacles. answer gates.\nstay in the flow.")
                                .font(VerbaFont.syne(.regular, size: 14))
                                .foregroundStyle(VerbaTheme.muted)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, 24)

                        // ── Personal bests ─────────────────────────────────
                        HStack(spacing: 12) {
                            bestCard(
                                value: bestScore > 0 ? "\(bestScore)" : "—",
                                label: "best score"
                            )
                            bestCard(
                                value: bestDistance > 0 ? "\(bestDistance) m" : "—",
                                label: "best distance"
                            )
                        }
                        .padding(.horizontal, 20)

                        // ── Question mode toggle ───────────────────────────
                        questionModeToggle
                            .padding(.horizontal, 24)

                        // ── How to play ────────────────────────────────────
                        howToPlayCard
                            .padding(.horizontal, 24)

                        Spacer(minLength: 16)

                        // ── Start button ───────────────────────────────────
                        Button {
                            showRunner = true
                        } label: {
                            Text("start run")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButtonStyle()
                        .padding(.horizontal, 24)

                        Spacer(minLength: 60)
                    }
                }
            }
            .navigationTitle("drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                }
            }
        }
        .onAppear(perform: loadBests)
        .fullScreenCover(isPresented: $showRunner, onDismiss: loadBests) {
            VerbaRunnerView()
        }
    }

    // MARK: - Sub-views

    private func bestCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VerbaFont.syne(.bold, size: 26))
                .foregroundStyle(VerbaTheme.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    private var questionModeToggle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("gate question style")
                .font(VerbaFont.syne(.semibold, size: 13))
                .foregroundStyle(VerbaTheme.ink)

            HStack(spacing: 8) {
                modeChip(
                    label: "multiple choice",
                    icon:  "list.bullet.rectangle",
                    mode:  .multipleChoice
                )
                modeChip(
                    label: "fill in answer",
                    icon:  "pencil",
                    mode:  .fillIn
                )
            }
        }
        .padding(16)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    private func modeChip(label: String, icon: String, mode: QuestionMode) -> some View {
        let selected = questionMode == mode
        return Button {
            questionMode = mode
            HapticManager.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(VerbaFont.syne(.medium, size: 12))
            }
            .foregroundStyle(selected ? .white : VerbaTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(selected ? VerbaTheme.green : VerbaTheme.green.opacity(0.0))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                    .stroke(selected ? VerbaTheme.green : VerbaTheme.border, lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.15), value: questionMode.rawValue)
        }
        .buttonStyle(.plain)
    }

    private var howToPlayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("how to play")
                .font(VerbaFont.syne(.semibold, size: 13))
                .foregroundStyle(VerbaTheme.ink)

            VStack(alignment: .leading, spacing: 8) {
                howToRow(icon: "arrow.left.arrow.right", text: "swipe left / right — change lane")
                howToRow(icon: "arrow.up",               text: "swipe up — jump over low obstacles")
                howToRow(icon: "arrow.down",             text: "swipe down — slide under obstacles")
                howToRow(icon: "bolt.fill",              text: "survive longer = higher score")
            }
        }
        .padding(16)
        .background(VerbaTheme.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.green.opacity(0.14), lineWidth: 1)
        )
    }

    private func howToRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VerbaTheme.green)
                .frame(width: 20)
            Text(text)
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.muted)
        }
    }

    // MARK: - Helpers

    private func loadBests() {
        bestScore    = UserDefaults.standard.integer(forKey: bestScoreKey)
        bestDistance = UserDefaults.standard.integer(forKey: bestDistanceKey)
    }
}
