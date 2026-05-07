import SwiftUI

enum VerbaTheme {

    // MARK: - Colors (matched exactly from verbadc.com)
    static let background   = Color(hex: "f5f0e8")  // warm parchment
    static let ink          = Color(hex: "1c1409")  // near-black brown
    static let green        = Color(hex: "0f7c67")  // primary teal-green
    static let greenDark    = Color(hex: "0a5245")  // darker teal
    static let brown        = Color(hex: "9b6343")  // warm brown
    static let cream        = Color(hex: "faecd4")  // light cream
    static let xpGold       = Color(hex: "f5c800")  // duck yellow / XP
    static let muted        = Color(hex: "6b5742")  // muted brown-grey
    static let card         = Color(hex: "fff8ef")  // off-white card
    static let danger       = Color.red

    // MARK: - Typography (matched from site: Instrument Serif + Syne)
    // Since these are Google Fonts we use closest native equivalents
    // OR register them as custom fonts (see setup instructions)

    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        italic
            ? .custom("InstrumentSerif-Italic", size: size)
            : .custom("InstrumentSerif-Regular", size: size)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Syne maps closest to a rounded sans in SwiftUI
        // Use .custom("Syne-Regular/Bold") if you add the font files
        switch weight {
        case .bold, .heavy, .black:
            return .custom("Syne-Bold", size: size)
        default:
            return .custom("Syne-Regular", size: size)
        }
    }

    // Fallback system fonts if custom fonts not added yet
    static func serifFallback(_ size: CGFloat, italic: Bool = false) -> Font {
        italic ? .system(size: size, design: .serif).italic()
               : .system(size: size, design: .serif)
    }

    static func sansFallback(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Corner Radius
    static let radiusS: CGFloat  = 8
    static let radiusM: CGFloat  = 14
    static let radiusL: CGFloat  = 20
    static let radiusXL: CGFloat = 32

    // MARK: - Shadow
    static func cardShadow() -> some View {
        return EmptyView()
    }
}

// MARK: - Color hex init
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
