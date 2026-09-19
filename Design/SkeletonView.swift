import SwiftUI

// MARK: - SkeletonView
//
// Reusable shimmering placeholder system. Designed to replace the
// bare `ProgressView()` spinners that previously rendered alone on
// every loading branch — small spinners feel UX-incomplete when the
// rest of the screen has structure. Skeletons show the SHAPE of
// what is about to arrive so users feel the screen is alive.
//
// Three primitives:
//   • SkeletonBloc     k(width:height:cornerRadius:)  single block
//   • SkeletonCardRow()                              mimics one card
//   • SkeletonList(count:)                            stack of rows
//
// All shimmer animations honor Reduce Motion: under
// `accessibilityReduceMotion == true` the shimmer phase is pinned
// to 0 (static blur) so users who explicitly opted out of motion
// do not see a pulsing screen.
//
// Palette reuses VerbaTheme tokens — no new colors so the
// skeleton chassis matches the cozy matcha FELIwS design system.

struct SkeletonBlock: View {
    var width: CGFloat = 120
    var height: CGFloat = 18
    var cornerRadius: CGFloat = 8

    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shimmerDuration: Double = 1.5

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Muted dusty-olive base wash — readable on every matcha surface.
            .fill(VerbaTheme.cozyOliveSubtext.opacity(0.15))
            .frame(width: width, height: height)
            .overlay(
                shimmer
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .allowsHitTesting(false)
            )
            .onAppear { startShimmer() }
    }

    private var shimmer: some View {
        // Diagonal clear→white→clear gradient that sweeps left → right,
        // producing a "scanning highlight" classic placeholder effect.
        // Plus-lighter blend keeps it bright on the muted base colour.
        LinearGradient(
            colors: [
                .clear,
                Color.white.opacity(0.55),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: phase * (width + 80))
        .blendMode(.plusLighter)
    }

    private func startShimmer() {
        guard !reduceMotion else {
            // Reduce Motion ON: stay static, no animation. The block is
            // visibly muted but motionless, which is the contract with
            // the user.
            phase = 0
            return
        }
        withAnimation(
            .linear(duration: shimmerDuration).repeatForever(autoreverses: false)
        ) {
            phase = 1.0
        }
    }
}

// MARK: - SkeletonCardRow
//
// Mimics one entry in the Library mission-card list: leading icon
// chip → VStack(title, subtitle) → trailing ribbon. Wrapped in the
// existing `cozyBlockCard()` chassis so the moment a real card mounts
// (when the data fetches) the layout distance is zero — no flash,
// no jump.

struct SkeletonCardRow: View {
    var titleWidth: CGFloat = 180
    var subtitleWidth: CGFloat = 110

    var body: some View {
        HStack(spacing: 14) {
            SkeletonBlock(width: 48, height: 48, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: titleWidth, height: 16, cornerRadius: 6)
                SkeletonBlock(width: subtitleWidth, height: 12, cornerRadius: 5)
            }
            Spacer(minLength: 8)
            SkeletonBlock(width: 56, height: 22, cornerRadius: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cozyBlockCard()
    }
}

// MARK: - SkeletonList
//
// Stack of `SkeletonCardRow`s sized to fill the same vertical region
// the real list will occupy. Default 4 rows matches the typical
// LibraryView "first impression" count.

struct SkeletonList: View {
    var rowCount: Int = 4
    /// Horizontal padding applied around the row stack. Default 18
    /// matches the typical mission-card grid padding of LibraryView;
    /// callers (modals, sheets, future integrations) override to match
    /// their parent chassis.
    var horizontalPadding: CGFloat = 18

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<max(rowCount, 0), id: \.self) { _ in
                SkeletonCardRow()
            }
        }
        .padding(.horizontal, horizontalPadding)
        // Animate the whole stack in so the swap from skeleton → real
        // data feels like content arrival, not render pop.
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - PaywallSkeleton
//
// Specific composition for PaywallView's offerings-loading branch:
// hero block (200pt tall), 2-button subhero, 3-card feature grid.
// Matches the actual PaywallView layout region so when offerings
// resolve the transition is layout-stable.

struct PaywallSkeleton: View {
    var body: some View {
        VStack(spacing: 24) {
            // Hero placeholder
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VerbaTheme.oliveBorder.opacity(0.08))
                .frame(maxWidth: .infinity, minHeight: 220)
                .overlay(
                    VStack(spacing: 14) {
                        SkeletonBlock(width: 160, height: 28, cornerRadius: 8)
                        SkeletonBlock(width: 220, height: 18, cornerRadius: 6)
                    }
                )
                .padding(.horizontal, 20)

            // 2-button subhero
            HStack(spacing: 12) {
                SkeletonBlock(height: 56, cornerRadius: 14)
                    .frame(maxWidth: .infinity)
                SkeletonBlock(height: 56, cornerRadius: 14)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

            // 3 feature rows
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SkeletonBlock(width: 36, height: 36, cornerRadius: 12)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 140, height: 14, cornerRadius: 5)
                            SkeletonBlock(width: 90, height: 11, cornerRadius: 4)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VerbaTheme.cozySage)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
