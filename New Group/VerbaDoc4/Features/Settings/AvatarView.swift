import SwiftUI

// MARK: - AvatarView
//
// Renders the capybara avatar entirely with SwiftUI shapes — no image assets.
// Pass a size; every measurement scales proportionally.
// Used everywhere: profile card, leaderboard rows, share image, onboarding.

struct AvatarView: View {
    let config: AvatarConfig
    let size: CGFloat

    var body: some View {
        ZStack {
            // 1. Background circle
            Circle()
                .fill(config.bgColor.color)
                .frame(width: size, height: size)

            // 2. Capybara body (soft shape behind head)
            Ellipse()
                .fill(config.furColor.color)
                .frame(width: size * 0.55, height: size * 0.28)
                .offset(y: size * 0.28)

            // 3. Ears (behind head)
            Group {
                ear(flipped: false)
                    .offset(x: -size * 0.20, y: -size * 0.22)
                ear(flipped: true)
                    .offset(x:  size * 0.20, y: -size * 0.22)
            }

            // 4. Head
            Ellipse()
                .fill(config.furColor.color)
                .frame(width: size * 0.62, height: size * 0.54)
                .offset(y: -size * 0.03)

            // 5. Snout
            Ellipse()
                .fill(config.furColor.snoutColor)
                .frame(width: size * 0.30, height: size * 0.20)
                .offset(y: size * 0.16)

            // 6. Nostrils
            HStack(spacing: size * 0.07) {
                Circle().fill(Color.black.opacity(0.55)).frame(width: size * 0.04)
                Circle().fill(Color.black.opacity(0.55)).frame(width: size * 0.04)
            }
            .offset(y: size * 0.20)

            // 7. Eyes
            CapybaraEyes(style: config.eyeStyle, size: size, furColor: config.furColor)
                .offset(y: -size * 0.04)

            // 8. Blush marks (optional)
            if config.blush {
                HStack(spacing: size * 0.26) {
                    blushMark
                    blushMark
                }
                .offset(y: size * 0.10)
            }

            // 9. Accessory (emoji floated above head)
            if config.accessory != .none {
                Text(config.accessory.emoji)
                    .font(.system(size: size * 0.32))
                    .offset(y: -size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Subcomponents

    private func ear(flipped: Bool) -> some View {
        ZStack {
            // Outer ear
            Ellipse()
                .fill(config.furColor.color)
                .frame(width: size * 0.16, height: size * 0.20)
            // Inner ear
            Ellipse()
                .fill(config.furColor.snoutColor.opacity(0.5))
                .frame(width: size * 0.08, height: size * 0.12)
        }
        .rotationEffect(.degrees(flipped ? 12 : -12))
    }

    private var blushMark: some View {
        Ellipse()
            .fill(Color(red: 0.98, green: 0.60, blue: 0.62).opacity(0.35))
            .frame(width: size * 0.12, height: size * 0.07)
    }
}

// MARK: - Capybara Eyes

private struct CapybaraEyes: View {
    let style   : AvatarConfig.EyeStyle
    let size    : CGFloat
    let furColor: AvatarConfig.FurColor   // needed to erase eyelid in sleepy mode

    var body: some View {
        HStack(spacing: size * 0.16) {
            singleEye
            singleEye
        }
    }

    @ViewBuilder
    private var singleEye: some View {
        let s = size * 0.09     // eye bounding size
        switch style {
        case .normal:
            ZStack {
                Circle().fill(Color.black).frame(width: s, height: s)
                Circle().fill(Color.white).frame(width: s * 0.35, height: s * 0.35)
                    .offset(x: s * 0.18, y: -s * 0.18)
            }
        case .happy:
            ArcShape(clockwise: false)
                .stroke(Color.black, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                .frame(width: s, height: s * 0.6)
        case .sleepy:
            ZStack {
                Circle().fill(Color.black).frame(width: s, height: s)
                // Erase top half with fur color to create droopy eyelid
                Rectangle()
                    .fill(furColor.color)
                    .frame(width: s * 1.1, height: s * 0.55)
                    .offset(y: -s * 0.27)
            }
        case .starry:
            Text("✦")
                .font(.system(size: s * 1.1, weight: .bold))
                .foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.15))
        case .cool:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black)
                .frame(width: s * 1.3, height: s * 0.65)
        }
    }
}

// MARK: - ArcShape (happy eye arc)

private struct ArcShape: Shape {
    let clockwise: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width * 0.6,
            startAngle: .degrees(210),
            endAngle: .degrees(330),
            clockwise: clockwise
        )
        return p
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        AvatarView(config: AvatarConfig(), size: 80)
        AvatarView(config: AvatarConfig(furColor: .rosePink, eyeStyle: .happy, blush: true, accessory: .flowerCrown, bgColor: .peach), size: 80)
        AvatarView(config: AvatarConfig(furColor: .midnight, eyeStyle: .cool, blush: false, accessory: .sunglasses, bgColor: .slate), size: 80)
        AvatarView(config: AvatarConfig(furColor: .caramel, eyeStyle: .starry, blush: true, accessory: .graduationCap, bgColor: .gold), size: 80)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
