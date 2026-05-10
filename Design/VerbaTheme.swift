import SwiftUI

struct VerbaTheme {
    // MARK: - Background Colors
    static let background = Color(.systemBackground)
    static let card = Color.white
    static let cardSecondary = Color(.systemGray6)
    
    // MARK: - Text Colors
    static let textMain = Color.black
    static let textSecondary = Color.gray
    static let textTertiary = Color(.systemGray)
    
    // MARK: - Brand Colors
    static let green = Color(red: 0.2, green: 0.8, blue: 0.4)      // #33CC66
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)      // #FFD700
    static let blue = Color(red: 0.0, green: 0.5, blue: 1.0)       // #0080FF
    static let purple = Color(red: 0.7, green: 0.3, blue: 0.9)     // #B34DE6
    
    // MARK: - Status Colors
    static let red = Color(red: 1.0, green: 0.2, blue: 0.2)        // #FF3333
    static let brown = Color(red: 0.6, green: 0.4, blue: 0.2)      // #996633
    static let orange = Color(red: 1.0, green: 0.6, blue: 0.0)     // #FF9900
    
    // MARK: - Shadows
    static let shadowLight = Color.black.opacity(0.07)
    static let shadowMedium = Color.black.opacity(0.15)
    static let shadowDark = Color.black.opacity(0.25)
    
    // MARK: - Corner Radius
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20
    
    // MARK: - Spacing
    static let spacingXSmall: CGFloat = 4
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let spacingXLarge: CGFloat = 32
}

// MARK: - Font Extension (if using custom fonts)
extension VerbaTheme {
    struct Font {
        static let heading1 = SwiftUI.Font.system(size: 28, weight: .bold, design: .default)
        static let heading2 = SwiftUI.Font.system(size: 20, weight: .semibold, design: .default)
        static let heading3 = SwiftUI.Font.system(size: 16, weight: .semibold, design: .default)
        static let body = SwiftUI.Font.system(size: 16, weight: .regular, design: .default)
        static let bodySmall = SwiftUI.Font.system(size: 14, weight: .regular, design: .default)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular, design: .default)
        static let button = SwiftUI.Font.system(size: 16, weight: .semibold, design: .default)
    }
}

// MARK: - Gradient Extension
extension VerbaTheme {
    static let gradientGreen = LinearGradient(
        gradient: Gradient(colors: [green, green.opacity(0.7)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let gradientGold = LinearGradient(
        gradient: Gradient(colors: [gold, orange]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
