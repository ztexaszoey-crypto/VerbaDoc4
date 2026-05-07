import SwiftUI
import Foundation

/// Single source of truth for VerbaDoc's design language
/// Matched exactly to verbadc.com with warm parchment, teal-green primary, and Instrument Serif + Syne typography
enum VerbaTheme {

    // MARK: - Colors (exact hex values from site)
    
    /// Warm parchment background - the base of the entire app
    static let background = Color(hex: "f5f0e8")
    
    /// Near-black warm brown for all body text and headings
    static let ink = Color(hex: "1c1409")
    
    /// Deep teal-green primary action color
    static let green = Color(hex: "0f7c67")
    
    /// Darker teal for pressed states and depth
    static let greenDark = Color(hex: "0a5245")
    
    /// Warm capybara brown for secondary accents
    static let brown = Color(hex: "9b6343")
    
    /// Light cream for card backgrounds
    static let cream = Color(hex: "faecd4")
    
    /// Duck yellow for rewards, XP, and celebratory moments
    static let xpGold = Color(hex: "f5c800")
    
    /// Muted brown-grey for secondary text and captions
    static let muted = Color(hex: "6b5742")
    
    /// Off-white card background
    static let card = Color(hex: "fff8ef")
    
    /// Standard red for destructive actions only
    static let danger = Color.red

    // MARK: - Typography
    
    /// Instrument Serif - for headings, display text, and personality
    /// Use italic variant liberally for handcrafted feel
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        if italic {
            return .custom("InstrumentSerif-Italic", size: size)
        }
        return .custom("InstrumentSerif-Regular", size: size)
    }

    /// Syne - for body copy, labels, buttons, UI text
    /// Use bold for emphasis and buttons
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName = weight == .bold || weight == .heavy ? "Syne-Bold" : "Syne-Regular"
        return .custom(fontName, size: size)
    }

    /// Fallback if custom fonts not yet registered - uses system serif
    static func serifFallback(_ size: CGFloat, italic: Bool = false) -> Font {
        if italic {
            return .system(size: size, design: .serif).italic()
        }
        return .system(size: size, design: .serif)
    }

    /// Fallback if custom fonts not yet registered - uses system sans
    static func sansFallback(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Typography Styles (pre-configured)
    
    /// Large display heading - 36pt Instrument Serif italic
    static let displayLarge = serif(36, italic: true)
    
    /// Medium display heading - 28pt Instrument Serif italic
    static let displayMedium = serif(28, italic: true)
    
    /// Body heading - 22pt Instrument Serif
    static let headingLarge = serif(22)
    
    /// Section heading - 18pt Instrument Serif
    static let headingMedium = serif(18)
    
    /// Small heading - 16pt Instrument Serif bold
    static let headingSmall = serif(16, weight: .bold)
    
    /// Body text - 16pt Syne regular
    static let bodyLarge = sans(16)
    
    /// Body text - 15pt Syne regular
    static let body = sans(15)
    
    /// Small body - 14pt Syne regular
    static let bodySmall = sans(14)
    
    /// Caption - 12pt Syne
    static let caption = sans(12)
    
    /// Small caption - 11pt Syne
    static let captionSmall = sans(11)
    
    /// Button text - 15pt Syne bold
    static let buttonLabel = sans(15, weight: .bold)
    
    /// Tab label - 12pt Syne bold
    static let tabLabel = sans(12, weight: .bold)

    // MARK: - Corner Radius (8pt base unit)
    
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20
    static let radiusXL: CGFloat = 32

    // MARK: - Spacing (8pt base unit)
    
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Shadows
    
    /// Soft card shadow - warm ink at 7% opacity
    static let shadowCard = Shadow(
        color: ink.opacity(0.07),
        radius: 12,
        x: 0,
        y: 4
    )
    
    /// Subtle shadow - warm ink at 5% opacity
    static let shadowSubtle = Shadow(
        color: ink.opacity(0.05),
        radius: 8,
        x: 0,
        y: 2
    )
    
    /// Gold reward glow - xpGold at 40% opacity
    static let shadowGold = Shadow(
        color: xpGold.opacity(0.4),
        radius: 8,
        x: 0,
        y: 4
    )
}

// MARK: - Color Initialization from Hex

extension Color {
    /// Initialize Color from hex string (e.g., "0f7c67")
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

// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}
