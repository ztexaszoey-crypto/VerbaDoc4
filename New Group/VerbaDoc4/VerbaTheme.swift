import SwiftUI

enum VerbaTheme {
    static let green  = Color(red: 0.35, green: 0.76, blue: 0.57)
    static let dark   = Color(red: 0.08, green: 0.18, blue: 0.14)
    static let surf   = Color(red: 0.13, green: 0.24, blue: 0.19)
    static let xpGold = Color(red: 1.00, green: 0.78, blue: 0.15)
    static let danger = Color(red: 0.93, green: 0.27, blue: 0.27)

    static let cornerMD: CGFloat = 16
    static let cornerLG: CGFloat = 22
}

struct VerbaButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(filled ? VerbaTheme.green : VerbaTheme.green.opacity(0.12))
            .foregroundColor(filled ? VerbaTheme.dark : VerbaTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.cornerMD, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension View {
    func verbaCard() -> some View {
        self
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.cornerLG, style: .continuous))
    }

    func solidCard(_ color: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        self
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.cornerLG, style: .continuous))
    }
}
