import SwiftUI

struct VerbaTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VerbaTypography.title)
            .foregroundStyle(VerbaTheme.textPrimary)
    }
}

struct VerbaSectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VerbaTypography.sectionHeader)
            .foregroundStyle(VerbaTheme.textPrimary)
    }
}

struct VerbaBody: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VerbaTypography.body)
            .foregroundStyle(VerbaTheme.textPrimary)
    }
}

struct VerbaSecondary: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VerbaTypography.secondary)
            .foregroundStyle(VerbaTheme.textSecondary)
    }
}
