import SwiftUI

struct PrimaryButton: View {
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
            .background(VerbaTheme.primary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.radiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
