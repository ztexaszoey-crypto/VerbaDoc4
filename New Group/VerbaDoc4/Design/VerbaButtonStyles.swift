import SwiftUI

// MARK: - Primary Button Style

struct VerbaButtonStyle: ButtonStyle {
    var filled: Bool = true
    var color: Color = VerbaTheme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                    .fill(filled ? color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                            .stroke(color, lineWidth: filled ? 0 : 2)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Gold XP Button Variant

struct VerbaGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(VerbaTheme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                    .fill(VerbaTheme.xpGold)
                    .shadow(color: VerbaTheme.xpGold.opacity(0.4), radius: 8, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style (Outline)

struct VerbaSecondaryButtonStyle: ButtonStyle {
    var color: Color = VerbaTheme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                    .stroke(color, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Destructive Button Style

struct VerbaDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(VerbaTheme.danger)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                    .stroke(VerbaTheme.danger.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Small Pill Button (for tags, secondary actions)

struct VerbaPillButtonStyle: ButtonStyle {
    var filled: Bool = true
    var color: Color = VerbaTheme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? color : Color.clear)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(color, lineWidth: filled ? 0 : 1.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
