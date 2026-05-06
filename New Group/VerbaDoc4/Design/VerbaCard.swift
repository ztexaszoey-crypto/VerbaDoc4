import SwiftUI

struct VerbaCardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(VerbaTheme.spacing16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusLarge, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
