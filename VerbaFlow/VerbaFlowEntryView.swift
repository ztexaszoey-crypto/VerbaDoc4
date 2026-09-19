import SwiftUI
import SwiftData

// MARK: - VerbaFlowEntryView
// Pick your deck → run as a capybara → answer questions to break barriers.
// Free users: demo deck only. Pro: any deck.

struct VerbaFlowEntryView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gate = ProGate.shared

    @State private var selectedDoc: Document? = nil
    @State private var showGame      = false
    @State private var showPaywall   = false
    @State private var animateCap    = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.10, green: 0.20, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle grid overlay
            GridPattern()
                .opacity(0.04)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(10)
                            .background(.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    Spacer()
                    if !gate.isPro {
                        proChip
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // ── Capybara hero ─────────────────────────────────────────
                VStack(spacing: 0) {
                    // Capybara emoji with bounce
                    CapyScholar(size: 80)
                        .offset(y: animateCap ? -8 : 0)
                        .animation(
                            .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                            value: animateCap
                        )
                        .shadow(color: VerbaTheme.green.opacity(0.4), radius: 20, x: 0, y: 8)

                    // Speed lines
                    HStack(spacing: 6) {
                        ForEach(0..<5) { i in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(.white.opacity(0.15))
                                .frame(width: CGFloat(20 + i * 8), height: 2)
                                .offset(x: animateCap ? -4 : 4)
                                .animation(
                                    .easeInOut(duration: 0.4 + Double(i) * 0.08)
                                        .repeatForever(autoreverses: true),
                                    value: animateCap
                                )
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 24)

                // ── Title ─────────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("VerbaFlow")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("run · dodge · study · repeat")
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                }
                .padding(.bottom, 36)

                // ── Deck picker ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("what are you studying?")
                        .font(VerbaFont.syne(.semibold, size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // Demo deck (always free)
                            deckChip(
                                title: "demo run",
                                icon: "gamecontroller",
                                isSelected: selectedDoc == nil,
                                isLocked: false
                            ) {
                                withAnimation(.spring(response: 0.3)) { selectedDoc = nil }
                            }

                            // Real decks (Pro)
                            ForEach(documents) { doc in
                                deckChip(
                                    title: doc.title,
                                    icon: "books.vertical",
                                    isSelected: selectedDoc?.id == doc.id,
                                    isLocked: !gate.isPro
                                ) {
                                    if gate.isPro {
                                        withAnimation(.spring(response: 0.3)) { selectedDoc = doc }
                                    } else {
                                        showPaywall = true
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 32)

                // ── How it works ──────────────────────────────────────────
                HStack(spacing: 0) {
                    howStep(icon: "figure.run", text: "run")
                    connector
                    howStep(icon: "xmark.octagon.fill", text: "barrier")
                    connector
                    howStep(icon: "brain.head.profile", text: "answer")
                    connector
                    howStep(icon: "bolt.fill", text: "break through")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)

                // ── Play button ───────────────────────────────────────────
                Button {
                    HapticManager.impact(.medium)
                    showGame = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("play now")
                            .font(VerbaFont.syne(.bold, size: 18))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [VerbaTheme.green, Color(red: 0.12, green: 0.60, blue: 0.38)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                    .shadow(color: VerbaTheme.green.opacity(0.4), radius: 16, x: 0, y: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .onAppear { animateCap = true }
        .fullScreenCover(isPresented: $showGame) {
            VerbaFlowGameView(document: selectedDoc)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Subviews

    private var proChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text("PRO feature")
                .font(VerbaFont.syne(.bold, size: 11))
        }
        .foregroundStyle(VerbaTheme.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(VerbaTheme.green.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VerbaTheme.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func deckChip(title: String, icon: String, isSelected: Bool, isLocked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))

                Text(title)
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(VerbaTheme.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? AnyShapeStyle(VerbaTheme.green.opacity(0.25))
                    : AnyShapeStyle(.white.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(
                        isSelected ? VerbaTheme.green.opacity(0.6) : .white.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
    }

    private func howStep(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.6))
            Text(text)
                .font(VerbaFont.syne(.medium, size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var connector: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.2))
    }
}

// MARK: - GridPattern (decorative background)

struct GridPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 32
            var x: CGFloat = 0
            while x <= size.width {
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(.white), lineWidth: 0.5)
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(.white), lineWidth: 0.5)
                y += spacing
            }
        }
    }
}
