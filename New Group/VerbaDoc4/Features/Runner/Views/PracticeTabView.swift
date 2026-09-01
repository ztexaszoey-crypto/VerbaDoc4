import SwiftUI
import SwiftData

// MARK: - PracticeTabView
//
// Hub for both learning modalities.
// "Study" → VerbaFlowView (cross-deck adaptive SRS session)
// "Run"   → RunLobbyView  (VerbaFlow Runner)
//
// Both presented as fullScreenCover so each view owns its own NavigationStack
// without nesting conflicts.  Environment objects (xpManager, streakManager,
// tabRouter, modelContext) are propagated automatically through the covers.

struct PracticeTabView: View {

    @Query private var documents: [Document]
    @EnvironmentObject private var tabRouter: TabRouter

    @State private var showStudy  = false
    @State private var showRunner = false

    private var hasDecks: Bool {
        documents.contains { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        Spacer(minLength: 20)

                        // ── Hero ───────────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("practice.")
                                .font(VerbaFont.serif(size: 34))
                                .foregroundStyle(VerbaTheme.ink)
                            Text("choose your mode.")
                                .font(VerbaFont.syne(.regular, size: 14))
                                .foregroundStyle(VerbaTheme.muted)
                        }
                        .padding(.horizontal, 24)

                        // ── Mode cards ─────────────────────────────────────────
                        VStack(spacing: 14) {
                            modeCard(
                                icon:     "bolt.fill",
                                title:    "study",
                                subtitle: "adaptive SRS · all your decks",
                                accent:   VerbaTheme.green
                            ) { showStudy = true }

                            modeCard(
                                icon:     "figure.run",
                                title:    "run",
                                subtitle: "dodge obstacles · answer gates",
                                accent:   Color(red: 0.85, green: 0.42, blue: 0.12)
                            ) { showRunner = true }
                        }
                        .padding(.horizontal, 20)

                        // Empty state hint — only shown to new users with no decks
                        if !hasDecks {
                            Button {
                                tabRouter.selected = .upload
                            } label: {
                                HStack(spacing: 12) {
                                    VerbaMascot(mood: .happy, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("add your first set to start")
                                            .font(VerbaFont.syne(.semibold, size: 14))
                                            .foregroundStyle(VerbaTheme.ink)
                                        Text("drop in notes or a PDF — takes 30 seconds")
                                            .font(VerbaFont.syne(.regular, size: 12))
                                            .foregroundStyle(VerbaTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(VerbaTheme.green)
                                }
                                .padding(14)
                                .background(VerbaTheme.green.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                        .stroke(VerbaTheme.green.opacity(0.20), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("practice")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $showStudy)  { VerbaFlowView() }
        .fullScreenCover(isPresented: $showRunner) { RunLobbyView() }
    }

    // MARK: - Mode Card

    private func modeCard(
        icon:     String,
        title:    String,
        subtitle: String,
        accent:   Color,
        action:   @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(VerbaFont.syne(.semibold, size: 17))
                        .foregroundStyle(VerbaTheme.ink)
                    Text(subtitle)
                        .font(VerbaFont.syne(.regular, size: 13))
                        .foregroundStyle(VerbaTheme.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VerbaTheme.muted)
            }
            .padding(16)
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
        }
    }
}
