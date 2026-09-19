import SwiftUI

struct MascotSpeech: View {
    let text: String
    let mood: VerbaMascot.Mood
    let mascotSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerbaMascot(mood: mood, size: mascotSize)

            // Speech bubble
            Text(text)
                .font(VerbaFont.syne(.medium, size: 14))
                .foregroundStyle(VerbaTheme.ink)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .stroke(VerbaTheme.border, lineWidth: 1)
                )

            Spacer(minLength: 0)
        }
    }
}
