import SwiftUI

// MARK: - VerbaTheme
//
// One note before anything else: Tests/VerbaThemeTests.swift (already
// in this project, not written here) invents a fictional "FELIwS
// migration" history to justify a bright lime-green (#A8D63C) and
// gold (#FFD700) palette. That migration never happened anywhere else
// in this project's real history, and the palette it demands directly
// contradicts VerbaErrorBanner's own real rule that green is reserved
// for mastery only. Treat that test file as unreliable — it's never
// even wired into a real target — and do NOT hand-tune colors to
// satisfy its specific hex assertions. This file defines every token
// real screens actually need, with values consistent with the warm
// cream/olive "paper" direction, not that test's invented palette.
//
// DELETE every other VerbaTheme.swift / HapticManager.swift in the
// project before adding this — duplicate type definitions are a
// guaranteed compile error.

enum VerbaTheme {

    // MARK: Background ladder
    static let bgTop    = Color(hex: "F7F1E4")
    static let bgMid    = Color(hex: "F1E9D6")
    static let bgBottom = Color(hex: "EDE4CE")
    static var bg: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
    static var creamGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgMid], startPoint: .top, endPoint: .bottom)
    }
    static let cream = bgMid   // legacy alias — same warm cream, not a separate color

    // MARK: Ink & text
    static let ink               = Color(hex: "211C16")
    static let darkOliveInk      = ink                        // legacy alias
    static let muted             = Color(hex: "6B5D48")
    static let mediumOliveMuted  = muted                      // legacy alias
    static let cozyOliveSubtext  = Color(hex: "7A7550")

    // MARK: Card surfaces (raised "clay tile" gradient, light to dark)
    static let cardTop    = Color(hex: "FBF6E9")
    static let cardMid    = Color(hex: "F2EAD6")
    static let cardBottom = Color(hex: "E4D9BB")
    static let card       = cardTop           // legacy alias — most call sites just need a flat card fill
    static let glossCream = cardTop           // same surface, name used by newer views

    static var cornerShine: RadialGradient {
        RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                        center: .topLeading, startRadius: 0, endRadius: 40)
    }

    // MARK: Recessed / sunken surfaces (input channels)
    static let channelFloor  = Color(hex: "DED2AF")
    static let channelShadow = Color(hex: "8A7C55")

    // MARK: Borders & shadow
    static let oliveBorder        = Color(hex: "6F6E45")
    static let border             = oliveBorder               // legacy alias
    static let oliveContactShadow = Color(hex: "3A3524")
    static func shadow(_ alpha: Double) -> Color {
        oliveContactShadow.opacity(alpha)
    }

    // MARK: Accents — each with one specific job, none overused
    static let cozyForest = Color(hex: "3F5A3E")   // icon fills, primary emphasis
    static let cozyLime   = Color(hex: "9FAE5A")   // muted gold-green "active" pop — NOT neon lime
    static let cozySage   = Color(hex: "8FA37A")
    static let cozyMatcha = Color(hex: "6B8E4E")
    static let cozyMustard = Color(hex: "C79A3D")

    // MARK: Reserved / semantic — green stays mastery-only, per VerbaErrorBanner's own rule
    static let green   = Color(hex: "4B6B3F")
    static let orange  = Color(hex: "B8703A")
    static let danger  = Color(hex: "93301F")
    static let yellow  = Color(hex: "C79A3D")   // same family as mustard — warm, not pure gold/neon
    static let flowerGold = yellow              // legacy alias

    // MARK: CTA gradient (a real button gradient, not lime-green)
    static let ctaTop    = Color(hex: "4C6B49")
    static let ctaBottom = Color(hex: "33472F")
    static var primaryCta: LinearGradient {
        LinearGradient(colors: [ctaTop, ctaBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Decorative chip / accent palette (status chips, small flourishes)
    static let amber      = Color(hex: "C9922E")
    static let sienna     = Color(hex: "A0552E")
    static let brown      = Color(hex: "6B4A2E")
    static let mint       = Color(hex: "8FBFA0")
    static let pistachio  = Color(hex: "A8C08A")
    static let sage       = cozySage
    static let sunflower  = Color(hex: "D9A63C")
    static var stickyNote: LinearGradient {
        LinearGradient(colors: [Color(hex: "F2D879"), Color(hex: "E0C15E")],
                        startPoint: .top, endPoint: .bottom)
    }

    // MARK: Capybara mascot render colors
    static let clayBody      = Color(hex: "9B7A54")
    static let clayBodyLight = Color(hex: "B8946A")
    static let clayBodyDark  = Color(hex: "7A5D3E")
    static let claySnout     = Color(hex: "D9C4A0")
    static let clayShadow    = Color(hex: "4A3B26")

    // MARK: Radii — the two ladders real screens actually call
    static let r8:  CGFloat = 8
    static let r12: CGFloat = 12
    static let r16: CGFloat = 16
    static let r20: CGFloat = 20
    static let r24: CGFloat = 24
    static let r28: CGFloat = 28
    static let r30: CGFloat = 30

    // MARK: Cozy block card constants (the hard "sticker" shadow look)
    static let cozyOffset: CGSize = CGSize(width: 0, height: 4)
    static let cozyRadius: CGFloat = r16
    static let cozyStroke: CGFloat = 2
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

// MARK: - HapticManager
enum HapticManager {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    #if canImport(UIKit)
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    #else
    static func impact() {}
    #endif

    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
