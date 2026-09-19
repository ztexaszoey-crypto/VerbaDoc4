import SwiftUI

enum VerbaFont {
    enum SyneWeight { case regular, medium, semibold, bold }

    static func syne(_ weight: SyneWeight, size: CGFloat) -> Font {
        switch weight {
        case .regular:  return .system(size: size, weight: .regular,  design: .rounded)
        case .medium:   return .system(size: size, weight: .medium,   design: .rounded)
        case .semibold: return .system(size: size, weight: .semibold, design: .rounded)
        case .bold:     return .system(size: size, weight: .bold,     design: .rounded)
        }
    }

    static func serif(size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    // MARK: - Body typography for the pastel era (Phase 1)
    //
    // Apple SF Pro Rounded via `.design(.rounded)` — Nunito/Fredoka bounce
    // without bundle overhead. Native Dynamic Type.
    static func bodyRounded(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - FELIwS hierarchy helpers (Phase 2)
    //
    // Three-tier hierarchy matching the FELIwS reference:
    //   - title   → hero numerals / screen headers, bouncy bold + design rounded
    //   - body    → comfortable reading via bodyRounded
    //   - caption → muted tags with letter-spacing for the "EVOLVE"-style chips

    /// Hero titles — bold rounded, slight letter-spacing via `.tracking(0.4)`.
    /// Use for screen titles, big numerals (XP, streak days).
    static func title(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Caption text — for muted chips like "EVOLVE", small tags.
    static func caption(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
            .monospacedDigit()
    }
}
