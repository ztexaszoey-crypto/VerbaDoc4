import SwiftUI

// MARK: - Typography Helpers

struct VerbaTypography {
    // Headings - using Instrument Serif for personality
    static let displayLarge = VerbaTheme.serif(36, italic: false)
    static let displayMedium = VerbaTheme.serif(32, italic: false)
    static let displaySmall = VerbaTheme.serif(28, italic: false)

    // Display italic - for emphasis and personality
    static let displayItalic = VerbaTheme.serif(28, italic: true)

    // Heading - smaller titles
    static let headingLarge = VerbaTheme.serif(24, italic: false)
    static let headingMedium = VerbaTheme.serif(20, italic: false)
    static let headingSmall = VerbaTheme.serif(18, italic: false)

    // Body copy - using Syne for clarity
    static let bodyLarge = VerbaTheme.sans(16, weight: .regular)
    static let bodyMedium = VerbaTheme.sans(15, weight: .regular)
    static let bodySmall = VerbaTheme.sans(14, weight: .regular)

    // Bold variants for emphasis
    static let bodyLargeBold = VerbaTheme.sans(16, weight: .bold)
    static let bodyMediumBold = VerbaTheme.sans(15, weight: .bold)
    static let bodySmallBold = VerbaTheme.sans(14, weight: .bold)

    // Labels and captions
    static let labelLarge = VerbaTheme.sans(14, weight: .semibold)
    static let labelMedium = VerbaTheme.sans(13, weight: .semibold)
    static let labelSmall = VerbaTheme.sans(12, weight: .semibold)

    // Caption text
    static let captionLarge = VerbaTheme.sans(12, weight: .regular)
    static let captionSmall = VerbaTheme.sans(11, weight: .regular)

    // Fallback versions (when custom fonts unavailable)
    static let displayLargeFallback = VerbaTheme.serifFallback(36, italic: false)
    static let headingLargeFallback = VerbaTheme.serifFallback(24, italic: false)
    static let bodyLargeFallback = VerbaTheme.sansFallback(16, weight: .regular)
    static let bodyLargeBoldFallback = VerbaTheme.sansFallback(16, weight: .bold)
}

// MARK: - Font Fallback Extensions

extension Font {
    static var displayLarge: Font { VerbaTypography.displayLarge }
    static var displayMedium: Font { VerbaTypography.displayMedium }
    static var displaySmall: Font { VerbaTypography.displaySmall }
    static var displayItalic: Font { VerbaTypography.displayItalic }

    static var headingLarge: Font { VerbaTypography.headingLarge }
    static var headingMedium: Font { VerbaTypography.headingMedium }
    static var headingSmall: Font { VerbaTypography.headingSmall }

    static var bodyLarge: Font { VerbaTypography.bodyLarge }
    static var bodyMedium: Font { VerbaTypography.bodyMedium }
    static var bodySmall: Font { VerbaTypography.bodySmall }

    static var bodyLargeBold: Font { VerbaTypography.bodyLargeBold }
    static var bodyMediumBold: Font { VerbaTypography.bodyMediumBold }
    static var bodySmallBold: Font { VerbaTypography.bodySmallBold }

    static var labelLarge: Font { VerbaTypography.labelLarge }
    static var labelMedium: Font { VerbaTypography.labelMedium }
    static var labelSmall: Font { VerbaTypography.labelSmall }

    static var captionLarge: Font { VerbaTypography.captionLarge }
    static var captionSmall: Font { VerbaTypography.captionSmall }
}
