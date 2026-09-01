import SwiftUI

// MARK: - DailyChallengeCard
//
// Compact challenge widget shown in LibraryView.
// Observes DailyChallengeManager for live progress updates.
// Awards challenge XP through XPManager once on completion.

struct DailyChallengeCard: View {
    @EnvironmentObject private var xpManager: XPManager
    @ObservedObject private var challengeManager = DailyChallengeManager.shared

    var body: some View {
        let challenge = challengeManager.todayChallenge
        let fraction  = challengeManager.progressFraction
        let done      = challengeManager.isCompleted

        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                        .fill(done ? VerbaTheme.green.opacity(0.12) : VerbaTheme.yellow.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: done ? "checkmark.circle.fill" : challenge.icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(done ? VerbaTheme.green : VerbaTheme.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("daily challenge")
                            .font(VerbaFont.syne(.semibold, size: 11))
                            .foregroundStyle(VerbaTheme.muted)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        if done {
                            Text("+\(XPSystem.xpForAction(.challengeCompletion)) xp")
                                .font(VerbaFont.syne(.semibold, size: 11))
                                .foregroundStyle(VerbaTheme.green)
                        }
                    }
                    Text(challenge.title)
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(VerbaTheme.ink)
                }

                Spacer()

                Text("\(challengeManager.progress)/\(challenge.goal)")
                    .font(VerbaFont.syne(.bold, size: 14))
                    .foregroundStyle(done ? VerbaTheme.green : VerbaTheme.ink)
                    .monospacedDigit()
            }

            // Description + progress bar
            VStack(alignment: .leading, spacing: 8) {
                Text(challenge.description)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)

                // Progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(VerbaTheme.ink.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(done ? VerbaTheme.green : VerbaTheme.yellow)
                            .frame(width: geo.size.width * fraction, height: 4)
                            .animation(.verba, value: fraction)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(16)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(done ? VerbaTheme.green.opacity(0.25) : VerbaTheme.border, lineWidth: 1.5)
        )
        .onChange(of: challengeManager.isCompleted) { _, completed in
            // xpAlreadyAwarded is persisted in UserDefaults — survives tab switches,
            // view recreations, and app relaunches. Guaranteed single award per day.
            if completed && !challengeManager.xpAlreadyAwarded {
                challengeManager.markXPAwarded()
                xpManager.award(.challengeCompletion)
                HapticManager.success()
            }
        }
    }
}
