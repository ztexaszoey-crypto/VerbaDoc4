import SwiftUI
import SwiftData

struct IdentityCardView: View {
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @Query private var documents: [Document]
    @AppStorage("profile.name") private var profileName: String = ""

    @State private var glowAmount: Double = 0.5
    @State private var showRankUp = false
    @State private var lastRank: Rank = .initiate

    private var rank: Rank { Rank.rank(for: xpManager.totalXP) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(rank.color, lineWidth: 1.5)
                )
                .shadow(color: rank.color.opacity(glowAmount), radius: 16)

            VStack(alignment: .leading, spacing: 14) {
                headerRow
                Divider().background(rank.color.opacity(0.25))
                xpRow
                Divider().background(rank.color.opacity(0.25))
                statsRow
            }
            .padding(20)
        }
        .scaleEffect(showRankUp ? 1.04 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showRankUp)
        .onAppear {
            lastRank = rank
            startGlow()
        }
        .onChange(of: xpManager.totalXP) { _, _ in
            let newRank = rank
            if newRank.rawValue > lastRank.rawValue {
                triggerRankUp()
                lastRank = newRank
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profileName.isEmpty ? "SCHOLAR" : profileName.uppercased())
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("RANK \(rank.rawValue + 1): \(rank.name.uppercased())")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(rank.color)
            }
            Spacer()
            Image(systemName: rankIcon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(rank.color)
        }
    }

    // MARK: - XP Bar

    private var xpRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("XP")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if rank.isMax {
                    Text("\(xpManager.totalXP) XP — MAX")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(rank.color)
                } else {
                    Text("\(xpManager.totalXP) / \(rank.maxXP)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rank.color.opacity(0.18))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rank.color)
                        .frame(
                            width: geo.size.width * rank.xpProgress(totalXP: xpManager.totalXP),
                            height: 6
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: xpManager.totalXP)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            cardStat(
                value: "\(streakManager.currentStreak)",
                label: "STREAK",
                icon: "flame.fill",
                color: .orange
            )
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 32)
            cardStat(
                value: "\(documents.count)",
                label: "DOCS",
                icon: "doc.text.fill",
                color: rank.color
            )
        }
    }

    private func cardStat(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var rankIcon: String {
        switch rank {
        case .initiate:  return "circle.dotted"
        case .scholar:   return "book.fill"
        case .analyst:   return "chart.bar.fill"
        case .architect: return "building.2.fill"
        case .master:    return "crown.fill"
        }
    }

    private func startGlow() {
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            glowAmount = 1.0
        }
    }

    private func triggerRankUp() {
        showRankUp = true
        HapticManager.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showRankUp = false
        }
    }
}
