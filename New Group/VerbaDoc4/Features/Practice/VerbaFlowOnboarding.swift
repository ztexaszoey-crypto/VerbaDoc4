import SwiftUI

// MARK: - VerbaFlowOnboarding
//
// First-session educational overlay. Appears once, explains the core mechanics.
// Skippable. After dismissal, never shown again.
//
// Design principles:
//   - Data-forward, not childish
//   - Uses the actual vocabulary the app uses (energy, modes, gate cards)
//   - Three focused steps, no more
//   - Feels like a briefing, not a tutorial

struct VerbaFlowOnboarding: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "bolt.fill",
            title: "energy tracks focus",
            body: "Your energy bar rises when you answer correctly and drops on misses. Low energy shifts the session into review or recovery mode — harder reinforcement to lock in weak concepts.",
            accentColor: .green
        ),
        OnboardingPage(
            icon: "flag.fill",
            title: "gate cards are checkpoints",
            body: "When a concept keeps slipping, it gets injected as a gate card — marked with a flag. A wrong gate answer means you'll see it again in two cards. The session won't let that gap stay open.",
            accentColor: .orange
        ),
        OnboardingPage(
            icon: "arrow.counterclockwise",
            title: "recovery reinforces weak spots",
            body: "When energy drops below 10%, the session enters recovery mode. Cards you've missed multiple times are queued for extra repetition. This is the system working — not a punishment.",
            accentColor: .red
        )
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { } // prevent tap-through

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.white : Color.white.opacity(0.30))
                            .frame(width: i == page ? 20 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.22), value: page)
                    }
                }
                .padding(.bottom, 28)

                // Page content
                let current = pages[page]

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(current.accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: current.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(current.accentColor)
                    }

                    VStack(spacing: 10) {
                        Text(current.title)
                            .font(VerbaFont.serif(size: 22))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text(current.body)
                            .font(VerbaFont.syne(.regular, size: 15))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)

                // Navigation
                HStack(spacing: 12) {
                    if page < pages.count - 1 {
                        Button("skip") {
                            dismiss()
                        }
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(.white.opacity(0.50))
                        .frame(maxWidth: .infinity)

                        Button("next →") {
                            withAnimation(.easeInOut(duration: 0.22)) { page += 1 }
                        }
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Button("got it — start drilling") {
                            dismiss()
                        }
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(Color(red: 0.13, green: 0.13, blue: 0.13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .transition(.opacity)
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: "verbadoc.flowOnboardingComplete")
        withAnimation(.easeOut(duration: 0.22)) { isPresented = false }
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let body: String
    let accentColor: Color
}
