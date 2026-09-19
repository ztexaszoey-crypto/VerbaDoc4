import SwiftUI

// MARK: - CapySurfersResultsView
//
// End-of-run screen. Now shows progression stats (XP earned, cards reviewed,
// best combo, streak credit) in addition to the original stats. SM-2-lite
// mastery writeback is prepped for a follow-up session that has access to
// the typed SwiftData ModelContext (currently performed by the host
// CapySurfersGameView via @Query, see commitEndRun).

struct CapySurfersResultsView: View {
    let state: CapySurfersState
    let onPlayAgain: () -> Void
    let onShop: () -> Void
    let onMenu: () -> Void

    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager

    @State private var animate = false
    @State private var showStats = false
    @State private var showProgress = false
    @State private var showButtons = false

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.06, green: 0.14, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glow orb
            Circle()
                .fill(VerbaTheme.green.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -80)
                .scaleEffect(animate ? 1.08 : 0.95)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animate)

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                VStack(spacing: 8) {
                    if state.isNewHighScore {
                        HStack(spacing: 6) {
                            TrophyIconView(size: 14, color: VerbaTheme.yellow)
                            Text("NEW BEST")
                                .font(VerbaFont.syne(.bold, size: 13))
                                .foregroundStyle(VerbaTheme.yellow)
                                .tracking(2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(VerbaTheme.yellow.opacity(0.15))
                        .clipShape(Capsule())
                        .scaleEffect(animate ? 1.04 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: animate)
                    }

                    Text(resultHeadline)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                .opacity(animate ? 1 : 0)
                .offset(y: animate ? 0 : -20)

                // ── Skin badge ────────────────────────────────────────────
                SkinBadgeView(skin: state.equippedSkin, size: 80)
                    .padding(.top, 20)
                    .scaleEffect(animate ? 1.0 : 0.6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.15), value: animate)

                // ── Stats card ────────────────────────────────────────────
                VStack(spacing: 0) {
                    statRow(
                        icon: "figure.run",
                        label: "Distance",
                        value: "\(state.distance)m",
                        highlight: state.isNewHighScore,
                        delay: 0.25
                    )
                    Divider().background(.white.opacity(0.08))
                    statRow(
                        icon: "circle.fill",
                        label: "Watermelons",
                        value: "+\(state.melonsThisRun)",
                        highlight: false,
                        delay: 0.35,
                        usesMelonIcon: true
                    )
                    Divider().background(.white.opacity(0.08))
                    statRow(
                        icon: "trophy",
                        label: "Best",
                        value: "\(state.highScore)m",
                        highlight: false,
                        delay: 0.45
                    )
                }
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 16)

                // ── Progression summary (NEW: XP / combo / streak / cards) ─
                VStack(spacing: 10) {
                    progressionRow(
                        icon: "sparkles",
                        tint: VerbaTheme.yellow,
                        text: "+\(state.xpEarnedThisRun) study XP earned",
                        detail: "session XP credited to your account"
                    )
                    progressionRow(
                        icon: "bolt.horizontal.fill",
                        tint: VerbaTheme.green,
                        text: "Best combo × \(state.bestComboThisRun)",
                        detail: "\(state.itemsCorrectThisRun) of \(state.cardsReviewedThisRun) quizzes correct"
                    )
                    progressionRow(
                        icon: "flame.fill",
                        tint: VerbaTheme.orange,
                        text: state.streakCreditedThisRun ? "Streak updated" : "Streak not updated",
                        detail: state.streakCreditedThisRun ? "Today counted toward your streak" : "Run too short"
                    )
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .opacity(showProgress ? 1 : 0)
                .offset(y: showProgress ? 0 : 12)

                // ── Total watermelons ─────────────────────────────────────
                HStack(spacing: 6) {
                    CoinIconView(size: 14)
                    Text("\(state.totalMelons) total watermelons")
                        .font(VerbaFont.syne(.medium, size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 14)
                .opacity(showStats ? 1 : 0)

                Spacer()

                // ── Buttons ───────────────────────────────────────────────
                VStack(spacing: 12) {
                    // Play again (primary)
                    Button(action: onPlayAgain) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.trianglehead.counterclockwise")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Play Again")
                                .font(VerbaFont.syne(.bold, size: 17))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [VerbaTheme.green, Color(red: 0.12, green: 0.60, blue: 0.38)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: VerbaTheme.green.opacity(0.4), radius: 16, x: 0, y: 6)
                    }

                    HStack(spacing: 12) {
                        // Shop
                        Button(action: onShop) {
                            HStack(spacing: 6) {
                                ShopCartIconView(size: 15)
                                Text("Shop")
                                    .font(VerbaFont.syne(.semibold, size: 15))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                        }

                        // Menu
                        Button(action: onMenu) {
                            HStack(spacing: 6) {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 13))
                                Text("Menu")
                                    .font(VerbaFont.syne(.semibold, size: 15))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(showButtons ? 1 : 0)
                .offset(y: showButtons ? 0 : 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                animate = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                showStats = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35)) {
                showProgress = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.50)) {
                showButtons = true
            }
        }
    }

    // MARK: - Helpers

    private var resultHeadline: String {
        if state.isNewHighScore { return "Personal best!" }
        if state.distance >= 1000 { return "Incredible run!" }
        if state.distance >= 500  { return "Great surf!" }
        if state.distance >= 200  { return "Not bad, capy!" }
        return "Keep practicing!"
    }

    @ViewBuilder
    private func statRow(icon: String, label: String, value: String, highlight: Bool, delay: Double, usesMelonIcon: Bool = false) -> some View {
        HStack {
            Group {
                if usesMelonIcon {
                    MelonIconView(size: 20)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22)
                }
            }

            Text(label)
                .font(VerbaFont.syne(.medium, size: 15))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(highlight ? VerbaTheme.yellow : .white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func progressionRow(icon: String, tint: Color, text: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(VerbaFont.syne(.bold, size: 14))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }
}
