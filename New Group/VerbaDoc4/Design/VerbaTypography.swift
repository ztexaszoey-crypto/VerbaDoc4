import SwiftUI

enum VerbaTypography {
    static let title:         Font = .system(size: 30, weight: .bold)
    static let sectionHeader: Font = .system(size: 19, weight: .semibold)
    static let body:          Font = .system(size: 16, weight: .regular)
    static let secondary:     Font = .system(size: 13, weight: .regular)
}

extension Font {
    static var verbaTitle:         Font { VerbaTypography.title }
    static var verbaSectionHeader: Font { VerbaTypography.sectionHeader }
    static var verbaBody:          Font { VerbaTypography.body }
    static var verbaSecondary:     Font { VerbaTypography.secondary }
}
