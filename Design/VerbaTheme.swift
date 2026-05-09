import SwiftUI

enum VerbaTheme {
    static let background   = Color(hex: "f5f0e8")
    static let ink          = Color(hex: "1c1409")
    static let green        = Color(hex: "0f7c67")
    static let greenDark    = Color(hex: "0a5245")
    static let brown        = Color(hex: "9b6343")
    static let cream        = Color(hex: "faecd4")
    static let xpGold       = Color(hex: "f5c800")
    static let muted        = Color(hex: "6b5742")
    static let card         = Color(hex: "fff8ef")
    static let danger       = Color.red

    static let radiusS: CGFloat  = 8
    static let radiusM: CGFloat  = 14
    static let radiusL: CGFloat  = 20
    static let radiusXL: CGFloat = 32
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}

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

extension View {
    func verbaCard(padding: CGFloat = 16) -> some View {
        modifier(VerbaCardModifier(padding: padding))
    }

    func solidCard(_ color: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        self
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusL, style: .continuous))
    }
}
