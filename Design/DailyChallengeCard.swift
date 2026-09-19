import SwiftUI

struct DailyChallengeCard: View {
    private static let tips: [String] = [
        "Try the 2-minute rule: if a card takes longer to recall, mark it missed.",
        "Study before sleep — memory consolidation happens overnight.",
        "Reading your notes aloud activates more memory pathways.",
        "Spaced repetition beats cramming every time. Trust the algorithm.",
        "Take a 5-minute walk before a study session to boost focus.",
        "The harder a card is to recall, the stronger the memory after you get it.",
        "Mix topics in a single session for better long-term retention.",
        "Testing yourself is 2× more effective than re-reading.",
        "Explain a concept in your own words to find gaps in your knowledge.",
        "Short daily sessions beat long weekend marathons.",
        "Ask 'why?' after every fact you learn to build richer connections.",
        "Sleep 7-9 hours — memory consolidation peaks during deep sleep.",
        "Review a deck within 24 hours of first learning it.",
        "If you miss a window, catching up is always better than skipping.",
        "Your brain learns best when slightly challenged — aim for ~85% accuracy.",
        "Interleave easy and hard cards for maximum retention.",
        "Pretend you're teaching the material to someone else.",
        "A short review session (5 cards) beats no session at all.",
        "Reduce distractions during study — even background music can interfere.",
        "Celebrate small wins. Streaks and mastery scores are real progress.",
    ]

    private var tip: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Self.tips[(dayOfYear - 1) % Self.tips.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(VerbaTheme.yellow)
                .padding(8)
                .background(VerbaTheme.yellow.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("daily tip")
                    .font(VerbaFont.syne(.semibold, size: 11))
                    .foregroundStyle(VerbaTheme.muted)
                    .textCase(.uppercase)
                    .tracking(1)

                Text(tip)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }
}
