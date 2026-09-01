import SwiftUI

// MARK: - VerbaMascot
//
// The capybara + duck mascot from verbadc.com.
// Use sparingly — loading states, empty states, celebrations, onboarding.
//
// SETUP: Add mascot image assets to Assets.xcassets:
//   "MascotHappy"     — default/success
//   "MascotThinking"  — loading/processing
//   "MascotSleeping"  — empty state / no content
//   "MascotDuck"      — duck companion (optional)
//
// Until assets are added, falls back to the capybara emoji with styling.

enum MascotMood {
    case happy      // celebrations, success, completions
    case thinking   // loading, generating, processing
    case sleeping   // empty states, no content
    case cheering   // streak milestones, rank-up
    case worried    // concepts slipping, consecutive misses ≥ 3
    case lockedIn   // high-accuracy session, concept mastered
}

struct VerbaMascot: View {
    var mood: MascotMood = .happy
    var size: CGFloat    = 80
    var animate: Bool    = false

    @State private var bounce   = false
    @State private var pulse    = false

    private var assetName: String {
        switch mood {
        case .happy:    return "MascotHappy"
        case .thinking: return "MascotThinking"
        case .sleeping: return "MascotSleeping"
        case .cheering: return "MascotHappy"
        case .worried:  return "MascotThinking"
        case .lockedIn: return "MascotHappy"
        }
    }

    // Fallback avatar eye style — maps mascot mood to capybara expression
    private var fallbackEyeStyle: AvatarConfig.EyeStyle {
        switch mood {
        case .happy:    return .happy
        case .thinking: return .normal
        case .sleeping: return .sleepy
        case .cheering: return .starry
        case .worried:  return .normal
        case .lockedIn: return .cool
        }
    }

    // Ambient glow for lockedIn — subtle, not Duolingo
    private var glowColor: Color? {
        switch mood {
        case .lockedIn: return VerbaTheme.green.opacity(0.25)
        case .cheering: return VerbaTheme.yellow.opacity(0.20)
        case .worried:  return VerbaTheme.orange.opacity(0.18)
        default:        return nil
        }
    }

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                AvatarView(
                    config: AvatarConfig(eyeStyle: fallbackEyeStyle, blush: mood == .happy || mood == .cheering),
                    size: size
                )
            }
        }
        // Ambient glow — only for emotionally significant moods
        .shadow(
            color: glowColor ?? .clear,
            radius: pulse ? size * 0.4 : size * 0.15
        )
        .scaleEffect(bounce ? 1.06 : 1.0)
        .onAppear {
            if animate || mood == .cheering || mood == .lockedIn {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    bounce = true
                }
            }
            if glowColor != nil {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

// MARK: - Mascot speech bubble

struct MascotSpeech: View {
    let text: String
    var mood: MascotMood = .happy
    var mascotSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VerbaMascot(mood: mood, size: mascotSize)

            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(VerbaFont.serif(size: 16))
                    .foregroundStyle(VerbaTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(VerbaTheme.card)
                    .clipShape(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                            .stroke(VerbaTheme.border, lineWidth: 1)
                    )
            }
        }
    }
}
