import SwiftUI
import Combine

enum AppTab { case library, upload, tutor, flow, settings }

final class TabRouter: ObservableObject {
    @Published var selected: AppTab = .library
}

// MARK: - RootTabView

struct RootTabView: View {
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var tabRouter: TabRouter

    @State private var showRankUpBanner = false
    @State private var newRank: Rank? = nil

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $tabRouter.selected) {
                LibraryView()
                    .tag(AppTab.library)
                UploadTabView()
                    .tag(AppTab.upload)
                TutorChatView()
                    .tag(AppTab.tutor)
                CapySurfersEntryView()
                    .tag(AppTab.flow)
                SettingsView()
                    .tag(AppTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VerbaTabBar(selected: $tabRouter.selected)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .padding(.top, 4)
                    .background(
                        // Gradient fade so the floating tab bar blends with whatever
                        // pastel backdrop the active tab has, but never black.
                        LinearGradient(
                            colors: [VerbaTheme.bgTop.opacity(0),
                                     VerbaTheme.bgTop.opacity(0.65),
                                     VerbaTheme.bgBottom.opacity(0.95)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
            }

            if showRankUpBanner, let rank = newRank {
                rankUpBanner(rank: rank)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                    .padding(.top, 8)
                    .padding(.horizontal, 18)
            }
        }
        .onAppear { xpManager.awardDailyLoginIfNeeded(); xpManager.resetPreviousRank() }
        .onChange(of: xpManager.totalXP) { _, _ in
            if let rank = xpManager.didRankUp() {
                newRank = rank
                withAnimation(.verba) { showRankUpBanner = true }
                HapticManager.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.verba) { showRankUpBanner = false }
                }
            }
        }
    }

    // MARK: - Rank-up banner (FELIwS pastel chunky chip)

    private func rankUpBanner(rank: Rank) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [VerbaTheme.ctaTop, VerbaTheme.ctaBottom],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2))
                    .overlay(
                        Circle().inset(by: 1.5)
                            .stroke(VerbaTheme.glossCream.opacity(0.80), lineWidth: 1)
                    )
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                            radius: 0, x: 0, y: 3)
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(VerbaTheme.darkOliveInk)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("rank up!")
                    .font(VerbaFont.syne(.bold, size: 14))
                    .foregroundStyle(VerbaTheme.darkOliveInk)
                Text("you're now a \(rank.name)")
                    .font(VerbaFont.syne(.medium, size: 12))
                    .foregroundStyle(VerbaTheme.mediumOliveMuted)
            }
            Spacer()
            Button {
                withAnimation(.verba) { showRankUpBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VerbaTheme.darkOliveInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(VerbaTheme.glossCream))
                    .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 1.2))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [VerbaTheme.cardTop, VerbaTheme.cardMid],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .inset(by: 2)
                .stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 1.2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.28),
                radius: 0, x: 0, y: 6)
        .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                radius: 16, x: 0, y: 4)
    }
}

// MARK: - VerbaTabBar (FELIwS pastel floating chunky chip)
//
// Each tab item is rendered against a single chunky cream chip pill.
// The selected tab uses a circular mint-icon chip with olive border
// (consistent with `pastelIconChipStyle`), lifted above the bar with
// a contact shadow. Unselected icons use medium olive muted and
// render flat on the bar surface.

struct VerbaTabBar: View {
    @Binding var selected: AppTab

    private let items: [(AppTab, String, String)] = [
        (.library,  "house.fill",              "Home"),
        (.upload,   "plus.circle.fill",         "Add"),
        (.tutor,    "text.bubble.fill",         "Tutor"),
        (.flow,     "hare.fill",                "Capy"),
        (.settings, "person.crop.circle.fill",   "You"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.0) { tab, icon, label in
                tabButton(tab: tab, icon: icon, label: label)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            VerbaTheme.creamGradient
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .inset(by: 2)
                .stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 1.2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                radius: 0, x: 0, y: 8)
        .shadow(color: VerbaTheme.glossCream.opacity(0.45),
                radius: 22, x: 0, y: 6)
    }

    private func tabButton(tab: AppTab, icon: String, label: String) -> some View {
        let isSelected = selected == tab

        return Button {
            guard selected != tab else { return }
            HapticManager.light()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                selected = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Chunky mint chip behind selected icon
                    if isSelected {
                        Circle()
                            .fill(LinearGradient(
                                colors: [VerbaTheme.ctaTop, VerbaTheme.ctaBottom],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(width: 46, height: 32)
                            .overlay(
                                Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                            )
                            .overlay(
                                Capsule()
                                    .inset(by: 1.5)
                                    .stroke(VerbaTheme.glossCream.opacity(0.80), lineWidth: 1)
                            )
                            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.32),
                                    radius: 0, x: 0, y: 4)
                            .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                                    radius: 10, x: 0, y: 3)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? VerbaTheme.darkOliveInk : VerbaTheme.mediumOliveMuted)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                }
                .frame(height: 32)

                Text(label.uppercased())
                    .font(VerbaFont.syne(isSelected ? .bold : .semibold, size: 9))
                    .tracking(1.0)
                    .foregroundStyle(isSelected ? VerbaTheme.darkOliveInk : VerbaTheme.mediumOliveMuted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
        // Phase 19 release wiring — VoiceOver surfaces for the
        // bottom tab bar. Uppercase 9-pt glyph is illegible to
        // screen-reader users; expose a spoken label + direction
        // hint and mark the active tab with `.isSelected`.
        .accessibilityLabel(label)
        .accessibilityHint(isSelected
            ? "Currently selected tab."
            : "Switches to the \(label) tab.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
