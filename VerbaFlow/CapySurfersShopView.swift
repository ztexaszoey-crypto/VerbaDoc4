import SwiftUI

// MARK: - CapySurfersShopView

struct CapySurfersShopView: View {
    @ObservedObject var state: CapySurfersState
    @Environment(\.dismiss) private var dismiss

    @State private var purchasedID: String? = nil
    @State private var equippedFlash = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Wallet ─────────────────────────────────────────
                        walletCard
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // ── Skin grid ──────────────────────────────────────
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(CapySkin.all) { skin in
                                SkinCell(
                                    skin: skin,
                                    isOwned: state.owns(skin),
                                    isEquipped: state.equippedID == skin.id,
                                    canAfford: state.totalMelons >= skin.price,
                                    flashID: purchasedID
                                ) {
                                    handleTap(skin)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Skin Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(VerbaTheme.green)
                }
            }
        }
    }

    // MARK: - Wallet

    private var walletCard: some View {
        HStack(spacing: 12) {
            MelonIconView(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Watermelons")
                    .font(VerbaFont.syne(.medium, size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(state.totalMelons)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(VerbaTheme.yellow)
            }
            Spacer()
            Image(systemName: "info.circle")
                .foregroundStyle(.white.opacity(0.3))
                .font(.system(size: 16))
        }
        .padding(18)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func handleTap(_ skin: CapySkin) {
        if state.owns(skin) {
            state.equip(skin)
            HapticManager.light()
        } else {
            let bought = state.buy(skin)
            if bought {
                purchasedID = skin.id
                state.equip(skin)
                HapticManager.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    purchasedID = nil
                }
            } else {
                HapticManager.medium()
            }
        }
    }
}

// MARK: - SkinCell

private struct SkinCell: View {
    let skin: CapySkin
    let isOwned: Bool
    let isEquipped: Bool
    let canAfford: Bool
    let flashID: String?
    let onTap: () -> Void

    private var isFlashing: Bool { flashID == skin.id }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {

                // Emoji / preview
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: skin.bodyColor.r, green: skin.bodyColor.g, blue: skin.bodyColor.b).opacity(0.25),
                                    Color(red: skin.accentColor.r, green: skin.accentColor.g, blue: skin.accentColor.b).opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    SkinBadgeView(skin: skin, size: 52)
                }

                // Name
                Text(skin.name)
                    .font(VerbaFont.syne(.bold, size: 13))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                // Price / status
                Group {
                    if isEquipped {
                        Label("Equipped", systemImage: "checkmark.circle.fill")
                            .font(VerbaFont.syne(.bold, size: 11))
                            .foregroundStyle(VerbaTheme.green)
                    } else if isOwned {
                        Text("Tap to equip")
                            .font(VerbaFont.syne(.medium, size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    } else if skin.price == 0 {
                        Text("Free")
                            .font(VerbaFont.syne(.bold, size: 11))
                            .foregroundStyle(VerbaTheme.green)
                    } else {
                        HStack(spacing: 4) {
                            CoinIconView(size: 11)
                            Text("\(skin.price)")
                                .font(VerbaFont.syne(.bold, size: 13))
                                .foregroundStyle(canAfford ? VerbaTheme.yellow : .white.opacity(0.3))
                        }
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEquipped
                          ? VerbaTheme.green.opacity(0.12)
                          : .white.opacity(isFlashing ? 0.14 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isEquipped ? VerbaTheme.green.opacity(0.5) :
                        isFlashing ? VerbaTheme.yellow.opacity(0.7) :
                        .white.opacity(0.08),
                        lineWidth: isEquipped || isFlashing ? 1.5 : 1
                    )
            )
            .scaleEffect(isFlashing ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFlashing)
            .opacity(!isOwned && !canAfford && skin.price > 0 ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
