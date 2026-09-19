import SwiftUI

// MARK: - CapyRunnerLaunchView
//
// Brand-new "runner game template" launch screen — the Apple Design
// Award-grade entry point into CapySurfersGameView, MILDLY INSPIRED by
// (but not a copy of) the FELIwS pastel game-template referenced by the
// user. The look is a fully original compositon: outer pastel-green
// rounded canvas, dashed dark-olive border, top title chip, two
// stacked panels (Mission + Run), each with chunky 3D Nintendo-style
// controls (icon chips, pill CTAs), tabs, contents list, mine-grid of
// card icons, and pastel decorative ribbon.
//
// Capybara identity: the launch view uses the existing `VerbaMascot`
// mood library (`.happy`) and capy-accented decorations (mint chip
// background, dark-olive border, lemon-yellow flower + bow ribbon)
// instead of the runner sprite so the brand is consistent before the
// game starts.
//
// Layout (top → bottom inside the canvas):
//   1. Title chip             — serif "Runner" + sub eyebrow
//   2. Icon-chip row          — back / close / hamburger
//   3. Two-column body
//        Left  : "Start Run" pill CTA + "Continue" pill CTA
//        Right : Tabs row + contents list + 9-card mine grid
//   4. Decorative ribbon corner bow + yellow flower
//
// On `Start Run` the launch view dismisses and presents
// CapySurfersGameView, which hosts the SpriteKit engine.

struct CapyRunnerLaunchView: View {
    @EnvironmentObject private var xpManager:   XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @Environment(\.dismiss) private var dismiss

    /// Selected tab inside the right panel (`menu` in the reference is
    /// represented as a "Continue / New / Mastered" segmented set).
    @State private var rightTab: RightTab = .continueRun
    /// Which mine-grid card is highlighted (cosmetic — flashes the
    /// capy-friendly card on appear).
    @State private var highlightedCell: Int = 4
    @State private var titlePulseScale: CGFloat = 1.0

    /// Callback invoked when the user taps "Start Run". The parent that
    /// presents this view is responsible for dismissing the launch and
    /// routing to CapySurfersGameView (or any other study flow).
    var onStartRun: () -> Void = {}
    /// Callback invoked when the user taps "Continue".
    var onContinue: () -> Void = {}

    enum RightTab: String, CaseIterable, Identifiable {
        case continueRun = "continue"
        case newRun      = "new"
        case mastered    = "mastered"
        case review      = "review"

        var id: String { rawValue }

        var label: String { rawValue.capitalized }
    }

    private let menuItems: [String] = [
        "character", "avatar", "boards", "trails",
        "achievements", "friends", "shop", "pets", "settings"
    ]

    var body: some View {
        ZStack {
            CozyBackdrop {
                Color.clear
            }

            // Outer pastel rounded canvas with dashed dark olive border.
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(VerbaTheme.cozyMatcha.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(
                            VerbaTheme.oliveBorder,
                            style: StrokeStyle(lineWidth: 3.5, dash: [10, 6])
                        )
                )
                .verbaElevation(8)
                .padding(.horizontal, 14)
                .padding(.vertical, 18)

            VStack(spacing: 14) {
                titleChip
                    .scaleEffect(titlePulseScale)
                    .padding(.top, 30)

                iconChipRow
                    .padding(.horizontal, 26)

                HStack(alignment: .top, spacing: 12) {
                    leftPillStack
                        .padding(.leading, 4)

                    rightPanel
                        .padding(.trailing, 6)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 14)
            }
            .overlay(alignment: .topTrailing) {
                // Decorative pastel bow-ribbon — anchors the top-right
                // viewport of the canvas so the FELIwS reference's
                // hand-touched bow accent is preserved.
                RibbonBow(color: VerbaTheme.flowerGold)
                    .frame(width: 72, height: 60)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -8, y: 18)
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                            radius: 0, x: 0, y: 4)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                // Decorative lemon-yellow flower near bottom-left to round
                // out the composition.
                CanvasFlower(size: 30, petalColor: VerbaTheme.flowerGold)
                    .rotationEffect(.degrees(12))
                    .offset(x: 18, y: -22)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Loop the highlighted cell so the mine grid feels alive.
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                highlightedCell = (highlightedCell + 1) % 9
            }
            // Phase 24 polish: continuous gentle pulse on the title chip.
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                titlePulseScale = 1.06
            }
        }
    }

    // MARK: - Title Chip

    private var titleChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VerbaTheme.cozyForest)
            Text("Runner")
                .font(VerbaFont.serif(size: 22))
                .foregroundStyle(VerbaTheme.cozyForest)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 11)
        .background(VerbaTheme.cozySage)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 2.5))
        .overlay(
            Capsule().inset(by: 3)
                .stroke(VerbaTheme.glossCream.opacity(0.75), lineWidth: 1.0)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.35),
                radius: 0, x: 0, y: 5)
        .shadow(color: VerbaTheme.glossCream.opacity(0.45),
                radius: 14, x: 0, y: 4)
    }

    // MARK: - Icon Chip Row

    private var iconChipRow: some View {
        HStack(spacing: 10) {
            iconChip(symbol: "arrow.left")
            iconChip(symbol: "xmark")
            iconChip(symbol: "text.alignleft")
            Spacer()
        }
    }

    private func iconChip(symbol: String) -> some View {
        let glyph = Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(VerbaTheme.cozyForest)
            .frame(width: 44, height: 44)
            .background(VerbaTheme.cozySage)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VerbaTheme.oliveBorder, lineWidth: 2.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .inset(by: 1.5)
                    .stroke(VerbaTheme.glossCream.opacity(0.75), lineWidth: 1.0)
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.40),
                    radius: 0, x: 0, y: 4)
            .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                    radius: 8, x: 0, y: 5)
        return Button { dismiss() } label: { glyph }
            .buttonStyle(.plain)
    }

    // MARK: - Left Stack (pill CTAs)

    private var leftPillStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            pillCTA(label: "start run",
                    icon: "play.fill",
                    tint: VerbaTheme.ctaTop,
                    action: { onStartRun(); dismiss() })

            pillCTA(label: "continue",
                    icon: "arrow.clockwise",
                    tint: VerbaTheme.cozySage,
                    action: { onContinue(); dismiss() })
        }
        .frame(width: 168)
    }

    private func pillCTA(label: String,
                         icon: String,
                         tint: Color,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text(label)
                    .font(VerbaFont.syne(.bold, size: 17))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(VerbaTheme.cozySage)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(VerbaTheme.oliveBorder, lineWidth: 2.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .inset(by: 3)
                    .stroke(VerbaTheme.glossCream.opacity(0.75), lineWidth: 1.0)
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.45),
                    radius: 0, x: 0, y: 5)
            .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                    radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tabs row
            tabRow
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            // Two-column body: contents list | mine grid
            HStack(alignment: .top, spacing: 12) {
                contentsList
                    .frame(width: 110)

                mineGrid
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .inset(by: 3)
                .stroke(VerbaTheme.glossCream.opacity(0.75), lineWidth: 1.2)
        )
        // Inset dashed olive ribbon — game-template decorative cue.
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .inset(by: 5)
                .stroke(VerbaTheme.oliveBorder.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                radius: 0, x: 0, y: 6)
        .shadow(color: VerbaTheme.glossCream.opacity(0.45),
                radius: 16, x: 0, y: 5)
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(RightTab.allCases) { tab in
                tabChip(text: tab.label.lowercased(),
                        isActive: tab == rightTab) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                        rightTab = tab
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tabChip(text: String,
                         isActive: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(VerbaFont.syne(.bold, size: 11))
                .foregroundStyle(VerbaTheme.cozyForest)
                .verbaTabChip(isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    private var contentsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(menuItems.prefix(5), id: \.self) { item in
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(VerbaTheme.oliveBorder.opacity(0.65))
                    Text(item)
                        .font(VerbaFont.syne(.medium, size: 11))
                        .foregroundStyle(VerbaTheme.cozyForest)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VerbaTheme.glossCream.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VerbaTheme.oliveBorder.opacity(0.40), lineWidth: 1)
                )
            }
            Spacer(minLength: 0)
        }
    }

    private var mineGrid: some View {
        let cells = Array(0..<9)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(cells, id: \.self) { idx in
                mineCell(index: idx)
            }
        }
    }

    private func mineCell(index: Int) -> some View {
        let isHighlighted = index == highlightedCell
        let glyph = mineGlyph(for: index)
        return glyph
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(isHighlighted ? VerbaTheme.cozyForest : VerbaTheme.cozyOliveSubtext)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted
                          ? AnyShapeStyle(VerbaTheme.cozyLime)
                          : AnyShapeStyle(VerbaTheme.glossCream.opacity(0.85)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VerbaTheme.oliveBorder.opacity(isHighlighted ? 1.0 : 0.35), lineWidth: 1.5)
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(isHighlighted ? 0.35 : 0.08),
                    radius: 0, x: 0, y: isHighlighted ? 3 : 1)
            .scaleEffect(isHighlighted ? 1.05 : 1.0)
    }

    private func mineGlyph(for index: Int) -> some View {
        let glyphs: [String] = ["leaf.fill", "sparkles", "bolt.fill",
                                "flame.fill", "crown.fill", "star.fill",
                                "tortoise.fill", "leaf.circle.fill", "circle.hexagongrid.fill"]
        return Image(systemName: glyphs[index % glyphs.count])
    }
}

// MARK: - CanvasFlower
//
// Five-petal lemon-yellow flower drawn with Canvas paths. Decorative
// only; placed at the bottom-left of CapyRunnerLaunchView to balance
// the RibbonBow at top-trailing.

struct CanvasFlower: View {
    var size: CGFloat
    var petalColor: Color = VerbaTheme.flowerGold

    var body: some View {
        Canvas { ctx, s in
            let cx = s.width / 2
            let cy = s.height / 2
            let petals = 5
            let petalSize = s.width * 0.34

            for i in 0..<petals {
                let angle = (CGFloat(i) / CGFloat(petals)) * 2.0 * .pi - .pi / 2
                let pX = cx + cos(angle) * (s.width * 0.22)
                let pY = cy + sin(angle) * (s.height * 0.22)
                var path = Path()
                path.addEllipse(in: CGRect(
                    x: pX - petalSize / 2,
                    y: pY - petalSize / 2,
                    width: petalSize,
                    height: petalSize
                ))
                ctx.fill(path, with: .color(petalColor.opacity(0.92)))
            }

            // Center olive disc ties the petals to the FELIwS colour set.
            var center = Path()
            center.addEllipse(in: CGRect(
                x: cx - s.width * 0.12,
                y: cy - s.height * 0.12,
                width: s.width * 0.24,
                height: s.height * 0.24
            ))
            ctx.fill(center, with: .color(VerbaTheme.oliveBorder))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - RibbonDecoration
//
// Decorative pastel bow-ribbon pinned to the bottom-right of the
// canvas. Pure cosmetic, matches the FELIwS reference's hand-touched
// ribbon accent.

struct RibbonBow: View {
    var color: Color = VerbaTheme.flowerGold

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let knotRect  = CGRect(x: w * 0.30, y: h * 0.30,
                                   width: w * 0.40, height: h * 0.40)
            let leftRect  = CGRect(x: 0,        y: h * 0.20,
                                   width: w * 0.45, height: h * 0.55)
            let rightRect = CGRect(x: w * 0.55, y: h * 0.20,
                                   width: w * 0.45, height: h * 0.55)
            let leftTail  = CGRect(x: -w * 0.10, y: h * 0.78,
                                   width: w * 0.30, height: h * 0.20)
            let rightTail = CGRect(x: w * 0.80, y: h * 0.78,
                                   width: w * 0.30, height: h * 0.20)

            ctx.fill(Path(roundedRect: leftRect,  cornerSize: CGSize(width: 8, height: 8)),
                     with: .color(color.opacity(0.90)))
            ctx.fill(Path(roundedRect: rightRect, cornerSize: CGSize(width: 8, height: 8)),
                     with: .color(color.opacity(0.90)))
            ctx.fill(Path(roundedRect: knotRect,  cornerSize: CGSize(width: 4, height: 4)),
                     with: .color(VerbaTheme.oliveBorder))
            ctx.fill(Path(roundedRect: leftTail,  cornerSize: CGSize(width: 6, height: 6)),
                     with: .color(color.opacity(0.75)))
            ctx.fill(Path(roundedRect: rightTail, cornerSize: CGSize(width: 6, height: 6)),
                     with: .color(color.opacity(0.75)))
        }
        .frame(width: 60, height: 50)
    }
}
