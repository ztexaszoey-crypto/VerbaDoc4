import SwiftUI

// MARK: - ClayGlassSystem
//
// Phase-3 visual language for the four primary navigation surfaces
// (Home / Add a Deck / Play / You). Every primitive below is shared
// across screens so the capybara's claymation-meets-glass identity is
// preserved end-to-end:
//
//   • ClayCardModifier            — 3D raised tile with layered shadow + corner shine
//   • FrostedGlassButtonStyle    — translucent green glass slab for hero CTAs
//   • RecessedChannelModifier    — input field carved into the clay surface
//   • AmberProgressBar           — recessed channel for %% bars + readiness
//   • ClayStatusChip             — 3D pill with the new earth-warm palette
//   • PaperTextureBackdrop       — pressed-paper backdrop, never flat
//   • ClayStatTile               — 3D stat block (mastered/learning/at-risk etc.)
//
// The design philosophy is "every surface has a story": a card is a
// pressed tile (raised, thick rim, cast shadow), an input is a carved
// channel (sunken, dark inner shadow, raised lip), a CTA is a chunky
// glass slab (translucent, top highlight, deep shadow). Together they
// produce the "premium claymation-meets-glass" aesthetic the FELIwS
// brief specifies — Nintendo-quality polish, no flat dashboards.

// MARK: - ClayCardModifier

/// Raised clay tile. Different from `PastelCardStyle` (which is the
/// FELIwS sticky-note) by virtue of having THREE stacked shadows
/// (contact · ambient · inset rim) and the heavier corner shine —
/// surfaces wider than cards (stat tiles, hero blocks) should use this.
struct ClayCardModifier: ViewModifier {
    var cornerRadius: CGFloat = VerbaTheme.r28
    var tintTop:     Color     = VerbaTheme.cardTop
    var tintBottom:  Color     = VerbaTheme.cardBottom
    var borderColor: Color     = VerbaTheme.oliveBorder
    var borderWidth: CGFloat   = 2.0
    var highlightOpacity: Double = 0.70
    var cornerShine: Bool      = true
    var lift: CGFloat          = 6

    func body(content: Content) -> some View {
        let corner = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background(
                LinearGradient(
                    colors: [tintTop, tintBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(corner)
            // Outer olive stroke (paint-line border).
            .overlay(corner.stroke(borderColor, lineWidth: borderWidth))
            // Inset cream rim — pair with the outer border so the rim
            // catches light and the surface feels built up, not painted on.
            .overlay(
                corner
                    .inset(by: borderWidth - 0.5)
                    .stroke(VerbaTheme.glossCream.opacity(highlightOpacity), lineWidth: 1.2)
            )
            // Corner shine radial bloom in upper-right (only when on).
            .overlay {
                if cornerShine {
                    GeometryReader { geo in
                        VerbaTheme.cornerShine
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(corner)
                            .allowsHitTesting(false)
                    }
                }
            }
            // Three layered shadows for premium 3D depth:
            //   1. Ambient olive contact (low blur, +Y)
            //   2. Cream diffuse halo (high blur, +Y) — keeps pastel feel
            //   3. Wider cream puff (medium blur, +Y) — page-floating cue
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.45),
                    radius: 0, x: 0, y: lift)
            .shadow(color: VerbaTheme.glossCream.opacity(0.45),
                    radius: 18, x: 0, y: lift + 4)
            .shadow(color: VerbaTheme.glossCream.opacity(0.30),
                    radius: 28, x: 0, y: lift + 8)
    }
}

extension View {
    /// 3D raised clay tile. Use on hero blocks, stat tiles, large
    /// "tile" surfaces (Hub cards, profile primary card, exam chip).
    func clayCard(cornerRadius: CGFloat = VerbaTheme.r28,
                  tintTop: Color = VerbaTheme.cardTop,
                  tintBottom: Color = VerbaTheme.cardBottom,
                  borderColor: Color = VerbaTheme.oliveBorder,
                  borderWidth: CGFloat = 2.0,
                  highlightOpacity: Double = 0.70,
                  cornerShine: Bool = true,
                  lift: CGFloat = 6) -> some View {
        modifier(ClayCardModifier(
            cornerRadius: cornerRadius,
            tintTop: tintTop,
            tintBottom: tintBottom,
            borderColor: borderColor,
            borderWidth: borderWidth,
            highlightOpacity: highlightOpacity,
            cornerShine: cornerShine,
            lift: lift
        ))
    }
}


// MARK: - RecessedChannelModifier
//
// A field that looks CARVED into the clay surface — not pasted on top.
// Implementation: dark olive inner border at the top edge + cream
// highlight at the bottom edge + slight darker floor fill, so the
// field reads as a sunken basin that your thumb could depress into.

struct RecessedChannelModifier: ViewModifier {
    var cornerRadius: CGFloat = VerbaTheme.r20
    var tint: Color = VerbaTheme.channelFloor
    var borderColor: Color = VerbaTheme.oliveBorder
    var contentInset: EdgeInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)

    func body(content: Content) -> some View {
        let corner = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .padding(contentInset)
            // Slightly darker floor so the channel reads SUNKEN.
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(corner)
            // Top-edge dark inner-shadow stroke (channel "lip" casting
            // a shadow onto the floor).
            .overlay(
                corner.strokeBorder(
                    LinearGradient(
                        colors: [VerbaTheme.channelShadow.opacity(0.55),
                                 VerbaTheme.channelShadow.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 2
                )
            )
            // Bottom-edge cream inner-stroke (light bouncing off the
            // bottom of the channel).
            .overlay(
                corner.strokeBorder(
                    LinearGradient(
                        colors: [VerbaTheme.glossCream.opacity(0.0),
                                 VerbaTheme.glossCream.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            )
            // Outer olive paint-line so the channel frames cleanly
            // against the cream surface.
            .overlay(corner.stroke(borderColor.opacity(0.85), lineWidth: 1.5))
            .contentShape(corner)
    }
}

extension View {
    /// Carved-in input field. Apply to deck-title, exam-date,
    /// youtube-url text fields, and the AI note-paste textarea.
    func recessedChannel(cornerRadius: CGFloat = VerbaTheme.r20,
                         tint: Color = VerbaTheme.channelFloor,
                         borderColor: Color = VerbaTheme.oliveBorder,
                         contentInset: EdgeInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)) -> some View {
        modifier(RecessedChannelModifier(
            cornerRadius: cornerRadius,
            tint: tint,
            borderColor: borderColor,
            contentInset: contentInset
        ))
    }
}

// MARK: - AmberProgressBar
//
// Recessed-channel progress bar. The trough is darker/on-shadow, the
// fill is mint on a recessed floor, and the cap pill at the right edge
// is a clay notch.

struct AmberProgressBar: View {
    var progress: Double  // 0.0…1.0
    var tint: Color       = VerbaTheme.ctaTop
    var height: CGFloat   = 10
    var showsCap: Bool    = true

    var body: some View {
        GeometryReader { geo in
            let p         = CGFloat(max(0, min(1, progress)))
            let fillWidth = max(8, (geo.size.width * p) - (showsCap ? 2 : 0))

            ZStack(alignment: .leading) {
                // Trough — darker recessed channel
                Capsule()
                    .fill(VerbaTheme.channelShadow.opacity(0.32))
                    .frame(height: height)

                // Top-edge inner shadow inside the trough
                Capsule()
                    .stroke(VerbaTheme.channelShadow.opacity(0.35), lineWidth: 1)
                    .frame(height: height)

                // Mint fill, raised clay feel
                Capsule()
                    .fill(LinearGradient(
                        colors: [tint, tint.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.0)
                    )
                    .overlay(
                        Capsule().inset(by: 1)
                            .stroke(VerbaTheme.glossCream.opacity(0.5), lineWidth: 0.8)
                    )
                    .frame(width: fillWidth, height: height)
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                            radius: 0, x: 0, y: 2)
                    .animation(.verba, value: p)

                if showsCap {
                    // Cap pill anchored at the right edge of the fill
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 1.2))
                        .overlay(Circle().inset(by: 1).stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 0.8))
                        .frame(width: height + 4, height: height + 4)
                        .offset(x: max(0, fillWidth - (height + 4) / 2))
                        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                                radius: 0, x: 0, y: 2)
                        .animation(.verba, value: p)
                }
            }
        }
        .frame(height: height + 4)
    }
}

// MARK: - ClayStatusChip
//
// 3D pill-shaped status chip (warning / alert / success badge).
// Worked example: "30 free AI generations left" pill.

struct ClayStatusChip: View {
    enum Variant { case mint, amber, sienna, cream }
    let label: String
    let icon: String?
    let variant: Variant

    init(_ label: String, icon: String? = nil, variant: Variant = .mint) {
        self.label = label
        self.icon = icon
        self.variant = variant
    }

    private var fillTop: Color {
        switch variant {
        case .mint:    return VerbaTheme.ctaTop
        case .amber:   return VerbaTheme.amber
        case .sienna:  return VerbaTheme.sienna
        case .cream:   return VerbaTheme.glossCream
        }
    }

    private var fillBottom: Color {
        switch variant {
        case .mint:    return VerbaTheme.ctaBottom
        case .amber:   return VerbaTheme.amber.opacity(0.85)
        case .sienna:  return VerbaTheme.sienna.opacity(0.85)
        case .cream:   return VerbaTheme.cardTop
        }
    }

    private var foreground: Color {
        switch variant {
        case .mint, .amber, .sienna: return VerbaTheme.darkOliveInk
        case .cream:                  return VerbaTheme.darkOliveInk
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(label)
                .font(VerbaFont.syne(.bold, size: 11))
                .tracking(0.6)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [fillTop, fillBottom],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.5)
        )
        .overlay(
            Capsule().inset(by: 1)
                .stroke(VerbaTheme.glossCream.opacity(0.60), lineWidth: 0.8)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                radius: 0, x: 0, y: 2)
    }
}


// MARK: - ClayStatTile
//
// A 3D stat block (mastered/learning/at-risk/day-streak etc.). The
// hero number is sculpted in mint, the supporting label below sits
// on a forged clay surface, and the molded-plastic icon sits in a
// recessed dimple at the top of the tile.

struct ClayStatTile: View {
    let value: String
    let label: String
    let icon: String
    let tone: Tone

    enum Tone { case mint, amber, sienna, cream, olive }

    private var iconBackground: Color {
        switch tone {
        case .mint:    return VerbaTheme.ctaTop
        case .amber:   return VerbaTheme.amber
        case .sienna:  return VerbaTheme.sienna
        case .cream:   return VerbaTheme.glossCream
        case .olive:   return VerbaTheme.mediumOliveMuted
        }
    }

    private var iconForeground: Color {
        switch tone {
        case .mint, .amber, .sienna: return VerbaTheme.darkOliveInk
        case .cream, .olive:          return VerbaTheme.darkOliveInk
        }
    }

    private var valueColor: Color {
        switch tone {
        case .mint:    return VerbaTheme.darkOliveInk
        case .amber:   return VerbaTheme.amber
        case .sienna:  return VerbaTheme.sienna
        case .cream:   return VerbaTheme.darkOliveInk
        case .olive:   return VerbaTheme.darkOliveInk
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Molded icon dimple at top
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [iconBackground, iconBackground.opacity(0.82)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 1.6))
                    .overlay(
                        Circle().inset(by: 1)
                            .stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 0.8)
                    )
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                            radius: 0, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconForeground)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)

            Text(label.uppercased())
                .font(VerbaFont.syne(.bold, size: 9))
                .tracking(0.8)
                .foregroundStyle(VerbaTheme.mediumOliveMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .clayCard(cornerRadius: VerbaTheme.r24,
                  tintTop: VerbaTheme.cream,
                  tintBottom: VerbaTheme.cardMid.opacity(0.55),
                  lift: 4)
    }
}

// MARK: - CapySurferSeparable helper
//
// Tiny helper for a `clayStatTile` with the default Verba spacing
// applied. Just sugar for call sites that don't want to type the
// full `ClayStatTile(value:label:icon:tone:)` constructor every time.
extension ClayStatTile {
    static func mastered(_ n: Int)  -> ClayStatTile { .init(value: "\(n)", label: "mastered",  icon: "checkmark.seal.fill", tone: .mint) }
    static func learning(_ n: Int)  -> ClayStatTile { .init(value: "\(n)", label: "learning",  icon: "arrow.up.circle.fill", tone: .amber) }
    static func atRisk(_ n: Int)    -> ClayStatTile { .init(value: "\(n)", label: "at risk",   icon: "exclamationmark.triangle.fill", tone: .sienna) }
    static func dayStreak(_ n: Int) -> ClayStatTile { .init(value: "\(n)", label: "day streak", icon: "flame.fill", tone: .amber) }
    static func studyDays(_ n: Int) -> ClayStatTile { .init(value: "\(n)", label: "study days", icon: "calendar", tone: .cream) }
}

// MARK: - CozyBackdrop (Phase 6 — pure matte matcha backdrop)
//
// Phase 6 brief: NO gradients, NO blurred blobs, NO pressed-paper
// noise, NO glassmorphic effects. The backdrop is a single solid
// matcha fill so the cozy-matte blocks (cards + buttons) read as
// physical wooden toys pinned to a flat moss board. Replaces both
// `PastelBackdrop` and `PaperTextureBackdrop` for all FELIwS
// surfaces that migrated to the toy-block aesthetic; any remaining
// legacy call sites continue to use the older wrappers unchanged.
//
// IMPLEMENTATION NOTE: same ViewBuilder convention as the other
// `*Backdrop` wrappers in this file — store the closure as a `let`,
// accept it through an `init(@ViewBuilder content:)` parameter so
// callers can pass multi-statement ViewBuilder closures at the
// call site `CozyBackdrop { ... }`.

struct CozyBackdrop<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            VerbaTheme.cozyMatcha
                .ignoresSafeArea()
            content()
        }
    }
}

// MARK: - CozyBlockButtonStyle (Phase 6 — matte 3D toy-block)
// -----------------------------------------------------------------------------
// Replaces FrostedGlassButtonStyle. The aesthetic is OPPOSITE the FELIwS
// frosted-glass slab: NO gradients, NO inner highlights, NO translucent
// fills, NO blurry shadows. Depth comes from a SOLID dark-olive base
// rectangle offset (4, 6) behind the lime face — the surface reads as a
// pressed wooden block, not a glass pane.
//
// Press state: base offset shrinks to (1, 1) so the block visibly
// depresses into its base. No scale transform, no opacity fade —
// physical compression only.
//
// TEXT RULE: do NOT pass a hardcoded `.frame(height: ...)` to the label.
// The label sizes to its intrinsic content; vertical padding drives the
// hit-target. For title text inside the label, apply
// `.lineLimit(1).minimumScaleFactor(0.5)` so long labels shrink instead
// of clipping or pushing the button off-row.
// -----------------------------------------------------------------------------

struct CozyBlockButtonStyle: ButtonStyle {
    /// Foreground fill of the button face. Defaults to vibrant lime.
    var fill: Color = VerbaTheme.cozyLime
    /// Dark-olive stroke + 3D base color. Always the forest token.
    var ink: Color  = VerbaTheme.cozyForest
    /// Foreground text color. Forest on lime (NEVER white).
    var foreground: Color = VerbaTheme.cozyForest
    /// 3D base offset in its pressed (resting) state. Phase 6 brief
    /// locks this at (4, 5) — not the (4, 6) earlier draft.
    var baseOffset: CGSize = VerbaTheme.cozyOffset
    /// 3D base offset when the button is actively pressed.
    var pressedOffset: CGSize = .init(width: 1, height: 1)
    /// Corner radius for both base + face.
    var cornerRadius: CGFloat = VerbaTheme.cozyRadius
    /// Stroke thickness in points. 4.5pt per Phase 6 brief.
    var strokeWidth: CGFloat = VerbaTheme.cozyStroke

    func makeBody(configuration: Configuration) -> some View {
        let offset = configuration.isPressed ? pressedOffset : baseOffset
        ZStack {
            // 3D base — solid forest, offset (4, 5) by default.
            // This is the ONLY source of depth. No shadows, no glow,
            // no glass, no material effects.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ink)
                .offset(offset)

            // Main face — solid fill, 4.5pt forest stroke.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ink, lineWidth: strokeWidth)
                )
                // The face sits flush over the base so the base
                // protrudes from the bottom-right corners only.
                .offset(
                    x: configuration.isPressed ? baseOffset.width - pressedOffset.width : 0,
                    y: configuration.isPressed ? baseOffset.height - pressedOffset.height : 0
                )

            // Foreground label. Phase 6 brief: text guards applied
            // automatically — every CozyBlock button title scales down
            // to fit a single line rather than clipping or wrapping.
            configuration.label
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        // Phase 6: fixedSize(horizontal: false, vertical: true) prevents
        // rigid height layout breaks — the block sizes to its content
        // vertically but stretches to fill its container horizontally.
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.18, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

extension View {
    /// Cozy toy-block CTA. Apply to "Generate with AI", "Study Now",
    /// "Surf Now", "add your first set" — every primary action.
    func cozyBlockButtonStyle(
        fill: Color = VerbaTheme.cozyLime,
        ink: Color  = VerbaTheme.cozyForest,
        foreground: Color = VerbaTheme.cozyForest,
        cornerRadius: CGFloat = VerbaTheme.cozyRadius,
        strokeWidth: CGFloat = VerbaTheme.cozyStroke
    ) -> some View {
        buttonStyle(CozyBlockButtonStyle(
            fill: fill, ink: ink, foreground: foreground,
            cornerRadius: cornerRadius, strokeWidth: strokeWidth
        ))
    }
}

// MARK: - CozyBlockCardModifier (Phase 6 — matte card chassis)
// -----------------------------------------------------------------------------
// Replaces ClayCardModifier. Same construction as CozyBlockButtonStyle
// but without the press-state animation and with a customizable fill.
// Every container \u2014 mission card, stat tile, hero block, document row
// \u2014 paints as a solid sage rectangle with a thick forest stroke and a
// solid forest base peeking from the bottom-right.
// -----------------------------------------------------------------------------

struct CozyBlockCardModifier: ViewModifier {
    var fill: Color = VerbaTheme.cozySage
    var ink: Color  = VerbaTheme.cozyForest
    var cornerRadius: CGFloat = VerbaTheme.cozyRadius
    /// Phase 6 brief: 3D base offset is (4, 5). Locked at the
    /// `VerbaTheme.cozyOffset` constant so cards + buttons always
    /// share the same extrusion depth.
    var baseOffset: CGSize = VerbaTheme.cozyOffset
    /// Phase 6 brief: stroke is 4.5pt — a confident bold outline that
    /// still lets smaller surfaces breathe.
    var strokeWidth: CGFloat = VerbaTheme.cozyStroke

    func body(content: Content) -> some View {
        ZStack {
            // 3D base — solid forest, offset (4, 5). This is the ONLY
            // source of depth. No shadows, no glow, no glass, no
            // material effects of any kind.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ink)
                .offset(baseOffset)
            // Face — solid fill + 4.5pt forest stroke.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ink, lineWidth: strokeWidth)
                )
            // Content. Caller is responsible for applying
            // .lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
            // to titles and wrapping internal text in
            // VStack(alignment: .leading, spacing: 4) so labels never
            // clip. fixedSize keeps the block from collapsing.
            content
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// Cozy toy-block card chassis. Apply to mission cards, stat tiles,
    /// hero blocks, document rows, settings rows.
    func cozyBlockCard(
        fill: Color = VerbaTheme.cozySage,
        ink: Color  = VerbaTheme.cozyForest,
        cornerRadius: CGFloat = VerbaTheme.cozyRadius,
        baseOffset: CGSize = VerbaTheme.cozyOffset,
        strokeWidth: CGFloat = VerbaTheme.cozyStroke
    ) -> some View {
        modifier(CozyBlockCardModifier(
            fill: fill, ink: ink,
            cornerRadius: cornerRadius,
            baseOffset: baseOffset,
            strokeWidth: strokeWidth
        ))
    }
}

// MARK: - CapyHeroPanel
//
// Reusable hero panel for the capybara mascot, used in LibraryView
// (Home) and as the "today's coaching voice" container. Wooden-frame
// clay border, mascot on the left, sparkling CTA on the right.

struct CapyHeroPanel<Content: View>: View {
    let mood: VerbaMascot.Mood
    let mascotSize: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // 3D clay bezel behind mascot
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [VerbaTheme.glossCream, VerbaTheme.cardTop],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: mascotSize + 16, height: mascotSize + 16)
                VerbaMascot(mood: mood, size: mascotSize)
            }
            .padding(8)
            .background(
                Circle()
                    .fill(LinearGradient(
                        colors: [VerbaTheme.cardTop, VerbaTheme.cardBottom],
                        startPoint: .top, endPoint: .bottom
                    ))
            )
            .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2))
            .overlay(
                Circle().inset(by: 1.5)
                    .stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.40),
                    radius: 0, x: 0, y: 4)
            .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                    radius: 14, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .clayCard(cornerRadius: VerbaTheme.r24,
                  tintTop: VerbaTheme.cardTop,
                  tintBottom: VerbaTheme.cardBottom,
                  lift: 5)
    }
}


// MARK: - BackwardsCompat — re-export the new amber tokens through the
// legacy `orange`/`danger` slots so the entire fleet of existing call
// sites (LibraryView, UploadTabView, CapySurfersEntryView,
// SettingsView, DocumentDetailView, …) silently inherits the warm
// earth palette without rewriting any line.
//
// This `typealias` is here as documentation; the actual aliases are
// defined in VerbaTheme.swift. Anyone reading this file should be made
// aware that `VerbaTheme.orange` now resolves to `VerbaTheme.amber`,
// and `VerbaTheme.danger` resolves to `VerbaTheme.sienna`.
