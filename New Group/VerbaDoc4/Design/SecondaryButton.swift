import SwiftUI

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VerbaTheme.spacing8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.clear)
            .foregroundStyle(VerbaTheme.primary)
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.radiusMedium, style: .continuous)
                    .stroke(VerbaTheme.primary, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
