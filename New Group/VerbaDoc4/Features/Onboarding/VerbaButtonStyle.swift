import SwiftUI

// MARK: - VerbaButtonStyle
//
// Phase 2: less round, less loud. Confident, not excitable.
// Pressed state: minimal — just a fast opacity drop.
// No scale bounce. No spring overshoot.

struct VerbaButtonStyle: ButtonStyle {
    var filled: Bool            = true
    var backgroundColor: Color  = VerbaTheme.green
    var foregroundColor: Color  = .white
    var cornerRadius: CGFloat   = VerbaTheme.r12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VerbaFont.syne(.medium, size: 14))
            .foregroundStyle(filled ? foregroundColor : backgroundColor)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                filled
                    ? backgroundColor
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        filled ? Color.clear : backgroundColor.opacity(0.4),
                        lineWidth: 0.5
                    )
            )
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Convenience

extension Button {
    func primaryButtonStyle(cornerRadius: CGFloat = VerbaTheme.r12) -> some View {
        self.buttonStyle(VerbaButtonStyle(cornerRadius: cornerRadius))
    }

    func outlineButtonStyle(color: Color = VerbaTheme.green, cornerRadius: CGFloat = VerbaTheme.r12) -> some View {
        self.buttonStyle(
            VerbaButtonStyle(filled: false, backgroundColor: color, cornerRadius: cornerRadius)
        )
    }

    func dangerButtonStyle(cornerRadius: CGFloat = VerbaTheme.r12) -> some View {
        self.buttonStyle(
            VerbaButtonStyle(backgroundColor: VerbaTheme.danger, cornerRadius: cornerRadius)
        )
    }
}

// MARK: - Tag / label chip
// Use RoundedRectangle instead of Capsule — less startup, more editorial.

struct VerbaTag: View {
    let label: String
    var color: Color = VerbaTheme.green
    var filled: Bool = false

    var body: some View {
        Text(label)
            .font(VerbaFont.syne(.medium, size: 11))
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(filled ? color : color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
    }
}
