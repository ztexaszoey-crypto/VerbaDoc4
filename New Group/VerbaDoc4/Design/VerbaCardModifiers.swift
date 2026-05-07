import SwiftUI

// MARK: - Card View Modifier

struct VerbaCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusL, style: .continuous)
                    .fill(VerbaTheme.card)
                    .shadow(color: VerbaTheme.ink.opacity(0.07), radius: 12, y: 4)
            )
    }
}

// MARK: - Elevated Card Modifier

struct VerbaElevatedCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusL, style: .continuous)
                    .fill(VerbaTheme.cream)
                    .shadow(color: VerbaTheme.ink.opacity(0.1), radius: 16, y: 6)
            )
    }
}

// MARK: - Input Field Modifier

struct VerbaInputFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                    .fill(VerbaTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusM, style: .continuous)
                    .stroke(
                        isFocused ? VerbaTheme.green : VerbaTheme.muted.opacity(0.3),
                        lineWidth: 1.5
                    )
            )
            .focused($isFocused)
    }
}

// MARK: - Extension Methods

extension View {
    func verbaCard(padding: CGFloat = 16) -> some View {
        modifier(VerbaCardModifier(padding: padding))
    }

    func verbaElevatedCard(padding: CGFloat = 16) -> some View {
        modifier(VerbaElevatedCardModifier(padding: padding))
    }

    func verbaInputField() -> some View {
        modifier(VerbaInputFieldModifier())
    }
}
