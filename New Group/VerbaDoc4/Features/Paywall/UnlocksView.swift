import SwiftUI

struct UnlocksView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var xpManager: XPManager

    @State private var showRedeem = false

    var body: some View {
        NavigationStack {
            List {
                commonSection
                rareSection
                eventSection
            }
            .navigationTitle("Unlocks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Redeem Code") { showRedeem = true }
                        .font(.subheadline)
                }
            }
            .sheet(isPresented: $showRedeem) {
                RedeemCodeView()
            }
        }
    }

    // MARK: - Common Tier

    private var commonSection: some View {
        Section("Common") {
            unlockRow(
                name: "Default Theme",
                detail: "Automatic",
                icon: "circle.fill",
                color: .gray,
                isUnlocked: true
            )
            unlockRow(
                name: "Standard Card",
                detail: "Automatic",
                icon: "rectangle.fill",
                color: .gray,
                isUnlocked: true
            )
        }
    }

    // MARK: - Rare Tier

    private var rareSection: some View {
        Section("Rare — XP Milestones") {
            unlockRow(
                name: "Alt Theme",
                detail: "500 XP",
                icon: "paintpalette.fill",
                color: Rank.scholar.color,
                isUnlocked: xpManager.totalXP >= 500
            )
            unlockRow(
                name: "Animated Frame",
                detail: "1000 XP",
                icon: "rectangle.dashed",
                color: Rank.analyst.color,
                isUnlocked: xpManager.totalXP >= 1000
            )
            unlockRow(
                name: "Background Pattern",
                detail: "1500 XP",
                icon: "squareshape.split.2x2",
                color: Rank.architect.color,
                isUnlocked: xpManager.totalXP >= 1500
            )
            unlockRow(
                name: "Signature Effect",
                detail: "2000 XP",
                icon: "sparkles",
                color: Rank.master.color,
                isUnlocked: xpManager.totalXP >= 2000
            )
        }
    }

    // MARK: - Event Tier

    private var eventSection: some View {
        Section("Event — Limited") {
            if appState.unlockedEventItems.isEmpty {
                Text("No event items unlocked yet. Redeem a code to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appState.unlockedEventItems).sorted(), id: \.self) { item in
                    unlockRow(
                        name: item,
                        detail: "Event",
                        icon: "star.fill",
                        color: .orange,
                        isUnlocked: true
                    )
                }
            }
        }
    }

    // MARK: - Row

    private func unlockRow(
        name: String,
        detail: String,
        icon: String,
        color: Color,
        isUnlocked: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: isUnlocked ? icon : "lock.fill")
                .font(.system(size: 18))
                .foregroundStyle(isUnlocked ? color : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VerbaTheme.success)
                    .font(.system(size: 16))
            }
        }
        .padding(.vertical, 2)
    }
}
