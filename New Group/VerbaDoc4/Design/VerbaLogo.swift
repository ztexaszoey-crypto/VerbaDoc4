import SwiftUI

// MARK: - Logo Context

enum LogoContext {
    case idle       // Static, full opacity
    case study      // Dimmed — non-distracting during study
    case loading    // Gentle opacity pulse
    case complete   // Brief scale pop, then settles
}

// MARK: - VerbaLogoView
//
// Clean logo renderer. `depth` adds a subtle black shadow only —
// no colored glows, no ambient rings, no pulsing halos.

struct VerbaLogoView: View {
    var context: LogoContext = .idle
    var size: CGFloat = 28
    var depth: Bool = false

    @State private var animating = false
    @State private var pulseDone = false

    private var targetOpacity: Double {
        switch context {
        case .idle:     return 1.0
        case .study:    return 0.50
        case .loading:  return animating ? 0.55 : 1.0
        case .complete: return pulseDone ? 1.0 : (animating ? 1.0 : 0.65)
        }
    }

    private var targetScale: Double {
        switch context {
        case .complete: return pulseDone ? 1.0 : (animating ? 1.08 : 1.0)
        default:        return 1.0
        }
    }

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            // Subtle lift shadow — black only, no color
            .shadow(
                color: Color.black.opacity(depth ? 0.14 : 0.0),
                radius: depth ? size * 0.14 : 0,
                x: 0,
                y: depth ? size * 0.06 : 0
            )
            .opacity(targetOpacity)
            .scaleEffect(targetScale)
            .onAppear { startAnimation() }
            .onChange(of: context) { _, _ in startAnimation() }
    }

    private func startAnimation() {
        switch context {
        case .loading:
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animating = true
            }
        case .complete:
            animating = false
            pulseDone = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.60)) {
                animating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                withAnimation(.easeOut(duration: 0.25)) {
                    pulseDone = true
                }
            }
        default:
            animating = false
            pulseDone = false
        }
    }
}

// MARK: - Navigation Bar Logo

/// Drop into any .toolbar { } block as a leading item.
struct VerbaNavLogo: ToolbarContent {
    var context: LogoContext = .idle

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            VerbaLogoView(context: context, size: 26)
        }
    }
}

// MARK: - Hero Logo (logo + wordmark only — no tagline clutter)

struct VerbaHeroLogo: View {
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 10) {
            VerbaLogoView(size: size, depth: true)

            Text("VerbaDoc")
                .font(.system(size: size * 0.30, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}
