import SwiftUI

enum VerbaTheme {
    static let background = Color(hex: "f5f0e8")
    static let ink = Color(hex: "1c1409")
    static let green = Color(hex: "0f7c67")
    static let greenDark = Color(hex: "0a5245")
    static let brown = Color(hex: "9b6343")
    static let cream = Color(hex: "faecd4")
    static let xpGold = Color(hex: "f5c800")
    static let muted = Color(hex: "6b5742")
    static let card = Color(hex: "fff8ef")
    static let dark = Color(hex: "1c1409")
    static let surf = Color(hex: "2c2215")
    static let danger = Color.red

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20
    static let radiusXL: CGFloat = 32

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        if italic {
            return .custom("InstrumentSerif-Italic", size: size)
        }
        return .custom("InstrumentSerif-Regular", size: size)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName = weight == .bold || weight == .heavy ? "Syne-Bold" : "Syne-Regular"
        return .custom(fontName, size: size)
    }

    static func serifFallback(_ size: CGFloat, italic: Bool = false) -> Font {
        if italic {
            return .system(size: size, design: .serif).italic()
        }
        return .system(size: size, design: .serif)
    }

    static func sansFallback(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}
