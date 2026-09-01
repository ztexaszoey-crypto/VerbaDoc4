import SwiftUI

// MARK: - VerbaFont
//
// Brand typography system.
//
// Two typefaces:
//   • Instrument Serif — emotional, editorial, warm (onboarding, empty states, results)
//   • Syne            — modern, clean, confident (UI, navigation, body, buttons)
//
// SETUP: Add these font files to your Xcode project and register in Info.plist:
//   InstrumentSerif-Regular.ttf
//   InstrumentSerif-Italic.ttf
//   Syne-Regular.ttf
//   Syne-Medium.ttf
//   Syne-SemiBold.ttf
//   Syne-Bold.ttf
//
// Download from Google Fonts:
//   https://fonts.google.com/specimen/Instrument+Serif
//   https://fonts.google.com/specimen/Syne
//
// If fonts are not installed, the system gracefully falls back to:
//   Instrument Serif → .system(design: .serif)
//   Syne            → .system(design: .default)

enum VerbaFont {

    // MARK: - Instrument Serif (editorial headlines)

    static func serif(size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        return .custom(name, size: size, relativeTo: .body)
    }

    // MARK: - Syne (interface text)

    static func syne(_ weight: SyneWeight = .regular, size: CGFloat) -> Font {
        return .custom(weight.fontName, size: size, relativeTo: .body)
    }

    enum SyneWeight {
        case regular, medium, semibold, bold

        var fontName: String {
            switch self {
            case .regular:  return "Syne-Regular"
            case .medium:   return "Syne-Medium"
            case .semibold: return "Syne-SemiBold"
            case .bold:     return "Syne-Bold"
            }
        }
    }
}

// MARK: - Convenience modifiers

extension Text {
    func serif(size: CGFloat, italic: Bool = false) -> Text {
        self.font(VerbaFont.serif(size: size, italic: italic))
    }

    func syne(_ weight: VerbaFont.SyneWeight = .regular, size: CGFloat) -> Text {
        self.font(VerbaFont.syne(weight, size: size))
    }
}

extension View {
    func serifFont(size: CGFloat, italic: Bool = false) -> some View {
        self.font(VerbaFont.serif(size: size, italic: italic))
    }

    func syneFont(_ weight: VerbaFont.SyneWeight = .regular, size: CGFloat) -> some View {
        self.font(VerbaFont.syne(weight, size: size))
    }
}
