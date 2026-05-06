import SwiftUI

enum VerbaTheme {
    // MARK: - Legacy Colors (kept for OnboardingView / SplashView / XP system)
    static let green  = Color(red: 0.35, green: 0.76, blue: 0.57)
    static let dark   = Color(red: 0.08, green: 0.18, blue: 0.14)
    static let surf   = Color(red: 0.13, green: 0.24, blue: 0.19)
    static let xpGold = Color(red: 1.00, green: 0.78, blue: 0.15)
    static let danger = Color(red: 0.93, green: 0.27, blue: 0.27)

    // MARK: - Design System Colors
    static let primary       = Color(red: 0.231, green: 0.510, blue: 0.992) // #3B82F6
    static let surface       = Color(red: 0.976, green: 0.980, blue: 0.984) // #F9FAFB
    static let border        = Color(red: 0.898, green: 0.910, blue: 0.922) // #E5E7EB
    static let textPrimary   = Color(red: 0.067, green: 0.090, blue: 0.157) // #111827
    static let textSecondary = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    static let success       = Color(red: 0.168, green: 0.756, blue: 0.492) // #2DD4BF
    static let error         = Color(red: 0.957, green: 0.263, blue: 0.208) // #F43F5E

    // MARK: - Spacing Grid
    static let spacing8:  CGFloat = 8
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner Radius
    static let radiusSmall:  CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge:  CGFloat = 16

    // MARK: - Legacy Corner Radius (kept for backward compatibility)
    static let cornerMD: CGFloat = 16
    static let cornerLG: CGFloat = 22
}

struct VerbaButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(filled ? VerbaTheme.primary : Color.clear)
            .foregroundColor(filled ? .white : VerbaTheme.primary)
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusMedium, style: .continuous)
                    .stroke(filled ? Color.clear : VerbaTheme.primary, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusMedium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension View {
    func verbaCard() -> some View {
        self
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    func solidCard(_ color: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        self
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.cornerLG, style: .continuous))
    }
}
