import SwiftUI

// MARK: - VerbaTheme
//
// This defines the exact token names TutorChatView.swift and
// VerbaErrorBanner.swift already reference (glossCream, oliveBorder,
// cozyForest, cozyLime, cozyOliveSubtext, oliveContactShadow, bgTop,
// bgBottom) — those files were written against this vocabulary but the
// definition itself was never pushed, so nothing currently compiles.
//
// Direction: warm, cozy, hand-made — cream paper and olive ink, thick
// borders, HARD offset shadows (not soft blurs) for a "paper sticker"
// feel. This is charm through specific material choices, not through a
// mascot or a rounded-friendly-SaaS font. No neon, no purple, no
// glassmorphism — those are explicitly off the table.
//
// DELETE both of the older VerbaTheme.swift files (root and Design/)
// before adding this one — three definitions of the same type name is
// a guaranteed redeclaration error, and this is the one every current
// view actually depends on.

enum VerbaTheme {

    // MARK: Background
    // Used as a top-to-bottom gradient (see TutorChatView's `.bg`
    // usage and the inputBar's fade) so the screen never feels flat.
    static let bgTop    = Color(hex: "F7F1E4")
    static let bgBottom = Color(hex: "EDE4CE")
    static var bg: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Ink & text
    static let ink               = Color(hex: "211C16")   // primary text
    static let muted             = Color(hex: "6B5D48")   // secondary/meta text
    static let cozyOliveSubtext  = Color(hex: "7A7550")   // softer secondary, e.g. "clear" label

    // MARK: Surfaces
    static let glossCream = Color(hex: "FBF6E9")   // card/bubble/input fill — lighter than bg so it reads as a raised layer

    // MARK: Borders & shadow
    // Thick, warm-olive strokes + a hard offset shadow (no blur) is the
    // whole "paper sticker" effect — deliberately not a soft SaaS shadow.
    static let oliveBorder        = Color(hex: "6F6E45")
    static let oliveContactShadow = Color(hex: "3A3524")

    // MARK: Accents
    // Two accents with distinct jobs, not one color doing everything:
    //   cozyForest — icon fills, primary emphasis (calm, grounded)
    //   cozyLime   — the one "active/ready" pop, e.g. the send button
    //                when there's text to send
    static let cozyForest = Color(hex: "3F5A3E")
    static let cozyLime   = Color(hex: "C7C15A")

    // MARK: Reserved / semantic
    // `green` is reserved for mastery and progress ONLY — VerbaErrorBanner's
    // own rule, kept here rather than reinvented: never use it for anything
    // else, including a "success" error state.
    static let green   = Color(hex: "4B6B3F")
    static let orange  = Color(hex: "B8703A")   // retryable errors — not alarming
    static let danger  = Color(hex: "93301F")   // errors the user must act on
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
//
// Adds the missing `.light()` case. TutorChatView calls it (the
// "clear conversation" button) but the existing HapticManager — the
// one every other screen in the old project already uses — only has
// success/impact/selection. Without this addition, TutorChatView
// fails to compile on that call alone, even with the theme fixed.

enum HapticManager {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

/*
WHAT TO DO WITH THIS FILE:

1. Delete both existing VerbaTheme.swift files (they conflict with
   this one and with each other).
2. Delete the OLD HapticManager.swift under Features/Onboarding/ once
   this one is in the project (keeps it — just adds `.light()` — but
   having two definitions of the same type is still an error).
3. Add this file to the project, in the target that includes
   TutorChatView.swift and VerbaErrorBanner.swift.
4. Also port over VerbaFont.swift from the old project
   (New Group/VerbaDoc4/Theme/VerbaFont.swift) — TutorChatView uses
   VerbaFont.serif(...) and VerbaFont.syne(...), and that file already
   works correctly, it's just sitting in the disconnected old snapshot.
   Copy it in as-is, no changes needed.
*/
