import SwiftUI

// MARK: - PremiumBackground
//
// Phase-6 simplified: solid matcha backdrop with three capped decorative
// orbs. Replaces the older pastel-gradient + blurred-blob + paper-grain
// layer cake. Any caller that previously hit `PremiumBackground { ... }`
// now wraps content in the canonical `CozyBackdrop` from
// ClayGlassSystem.swift.

struct PremiumBackground: View {

    var body: some View {
        ZStack {
            VerbaTheme.cozyMatcha
                .ignoresSafeArea()
            orb(color: VerbaTheme.cozyLime.opacity(0.20),
                size: 280, x: -100, y: -160)
            orb(color: VerbaTheme.cozySage,
                size: 240, x: 120,  y: 220)
        }
    }

    private func orb(color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
            .blur(radius: 80)
    }
}

// MARK: - ScaleButtonStyle
//
// Subtle scale + opacity compression on press. Equivalent to the
// previously-private copy inside FlashcardStudyView, now consolidated
// here as a shared utility.

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
