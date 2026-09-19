import SwiftUI

// MARK: - VerbaMascot
// Drawn capybara — the VerbaDoc mascot.
// Replaces emoji placeholder everywhere in the app.
//
// Phase-3 upgrade: the capybara is now painted as a *clay figurine*
// with directional shading (key + fill + rim) and a chunky contact
// shadow beneath the body, so the silhouette reads as a 3D
// collectible rather than a flat vector drawing. We lose the ability
// to draw on a per-pixel basis typical of spritekit-style games,
// but we gain rendering purity (vector), crisp scaling, and the
// ability to recolor via VerbaTheme tokens.

struct VerbaMascot: View {
    enum Mood {
        case happy, thinking, excited, calm

        var background: Color {
            switch self {
            case .happy:    return VerbaTheme.ctaTop.opacity(0.18)
            case .thinking: return VerbaTheme.channelFloor.opacity(0.55)
            case .excited:  return VerbaTheme.sunflower.opacity(0.30)
            case .calm:     return VerbaTheme.mint.opacity(0.50)
            }
        }

        // Eye expression offset (y) for mood
        var eyeSquint: CGFloat {
            switch self {
            case .excited: return -0.02
            default:       return 0
            }
        }

        var mouthCurve: CGFloat {
            switch self {
            case .happy, .excited: return 1
            case .calm:            return 0.4
            case .thinking:        return -0.3
            }
        }
    }

    let mood: Mood
    let size: CGFloat

    var body: some View {
        // Ground-shadow under the figurine so it doesn't float in
        // empty space. Sized to ~28% of figure height, dark olive, soft.
        ZStack {
            // Ground ellipse shadow (under the figurine)
            Ellipse()
                .fill(VerbaTheme.oliveContactShadow.opacity(0.30))
                .frame(width: size * 0.78, height: size * 0.18)
                .offset(y: size * 0.30)
                .blur(radius: 2.5)

            // Soft halo behind mascot — adds warmth + reads as "clay"
            Circle()
                .fill(mood.background)
                .frame(width: size, height: size)
                .blur(radius: 0)

            CapybaraDrawing(mood: mood, size: size * 0.74)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CapybaraDrawing
//
// Multi-pass claymation rendering. Each body part is approximated
// as a sum of:
//   1. Cast shadow at the bottom edge of the part
//   2. Crease line where parts meet (head / body separation)
//   3. Base palette fill
//   4. Volumetric body shading — radial gradient offset to one side
//      simulating a directional light key
//   5. Rim light highlight — thin ellipse offset to the opposite side
//      from the key, providing the "holdable clay figurine" cue
//   6. Specular highlight — small bright dot at the snout tip +
//      tiny sparkle dots on the eyes
//
// The passes share `bodyColor` so re-tinting is a single-token swap.

struct CapybaraDrawing: View {
    let mood: VerbaMascot.Mood
    let size: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let s       = size
            let cx      = s / 2
            let cy      = s / 2

            // Direction of key light (top-left), so:
            //   • shadow side = bottom-right of every ellipse
            //   • rim light  = top-left of every ellipse
            let bodyColor  = VerbaTheme.clayBody
            let bodyDark   = VerbaTheme.clayBodyDark
            let bodyLight  = VerbaTheme.clayBodyLight
            let snoutColor = VerbaTheme.claySnout
            let shadowCol  = VerbaTheme.clayShadow
            let shine      = Color.white.opacity(0.92)

            // ---- Cast shadow (under body) --------------------------------
            let shadowRect = CGRect(x: cx - s*0.36, y: cy + s*0.30,
                                     width: s*0.72, height: s*0.10)
            ctx.fill(
                Path(ellipseIn: shadowRect),
                with: .color(shadowCol.opacity(0.45))
            )

            // ---- BODY ----------------------------------------------------
            // Cast shadow on body — small dark ring tucked under the head
            let bodyRect = CGRect(x: cx - s*0.36, y: cy - s*0.10,
                                   width: s*0.72, height: s*0.55)
            ctx.fill(Path(ellipseIn: bodyRect), with: .color(bodyDark.opacity(0.85)))

            // Base body fill
            ctx.fill(Path(ellipseIn: bodyRect), with: .color(bodyColor))

            // Volumetric shading — radial gradient offset to bottom-right
            // simulating a key light from upper-left.
            let bodyShade = CGRect(x: cx - s*0.40, y: cy - s*0.10,
                                    width: s*0.80, height: s*0.55)
            ctx.fill(
                Path(ellipseIn: bodyShade),
                with: .radialGradient(
                    Gradient(colors: [bodyColor.opacity(0.0),
                                       bodyDark.opacity(0.55)]),
                    center: CGPoint(x: cx + s*0.20, y: cy + s*0.30),
                    startRadius: s*0.10,
                    endRadius: s*0.55
                )
            )

            // Rim light — thin ellipse on upper-left side of body
            let rimBody = CGRect(x: cx - s*0.40, y: cy - s*0.16,
                                  width: s*0.20, height: s*0.10)
            ctx.fill(
                Path(ellipseIn: rimBody),
                with: .color(bodyLight.opacity(0.55))
            )

            // ---- HEAD ----------------------------------------------------
            let headRect = CGRect(x: cx - s*0.30, y: cy - s*0.52,
                                   width: s*0.60, height: s*0.54)

            // Cast shadow under head (on top of body — slight darker seam)
            let headShadow = CGRect(x: cx - s*0.30, y: cy - s*0.04,
                                     width: s*0.60, height: s*0.06)
            ctx.fill(Path(ellipseIn: headShadow), with: .color(shadowCol.opacity(0.30)))

            // Head base
            ctx.fill(Path(ellipseIn: headRect), with: .color(bodyColor))

            // Head volumetric shading — same gradient recipe as body
            ctx.fill(
                Path(ellipseIn: headRect),
                with: .radialGradient(
                    Gradient(colors: [bodyColor.opacity(0.0),
                                       bodyDark.opacity(0.55)]),
                    center: CGPoint(x: cx + s*0.20, y: cy - s*0.05),
                    startRadius: s*0.05,
                    endRadius: s*0.40
                )
            )

            // Head rim light — tiny bright sliver at top-left of head
            let rimHead = CGRect(x: cx - s*0.32, y: cy - s*0.55,
                                  width: s*0.18, height: s*0.08)
            ctx.fill(
                Path(ellipseIn: rimHead),
                with: .color(bodyLight.opacity(0.65))
            )

            // ---- EARS ----------------------------------------------------
            // Each ear: cast-shadow + base + rim
            for earX in [cx - s*0.30, cx + s*0.16] as [CGFloat] {
                let earRect = CGRect(x: earX, y: cy - s*0.62,
                                      width: s*0.14, height: s*0.12)
                // Cast shadow on ear base
                let earShadow = CGRect(x: earX, y: cy - s*0.50,
                                        width: s*0.14, height: s*0.04)
                ctx.fill(Path(ellipseIn: earShadow), with: .color(shadowCol.opacity(0.30)))
                // Base ear
                ctx.fill(Path(ellipseIn: earRect), with: .color(bodyDark))
                // Rim
                let earRim = CGRect(x: earX + s*0.01, y: cy - s*0.62,
                                     width: s*0.07, height: s*0.04)
                ctx.fill(Path(ellipseIn: earRim), with: .color(bodyColor.opacity(0.7)))
            }

            // ---- SNOUT / MOUTH AREA --------------------------------------
            let snoutRect = CGRect(x: cx - s*0.18, y: cy - s*0.18,
                                    width: s*0.36, height: s*0.24)
            // Recessed dimple (darker shadow at top of snout)
            let snoutDimple = CGRect(x: cx - s*0.18, y: cy - s*0.20,
                                      width: s*0.36, height: s*0.04)
            ctx.fill(Path(ellipseIn: snoutDimple), with: .color(shadowCol.opacity(0.18)))
            // Snout base
            ctx.fill(Path(ellipseIn: snoutRect), with: .color(snoutColor))
            // Snout shading
            ctx.fill(
                Path(ellipseIn: snoutRect),
                with: .radialGradient(
                    Gradient(colors: [snoutColor.opacity(0.0),
                                       bodyDark.opacity(0.20)]),
                    center: CGPoint(x: cx - s*0.10, y: cy + s*0.04),
                    startRadius: s*0.02,
                    endRadius: s*0.20
                )
            )

            // ---- NOSE ----------------------------------------------------
            let noseRect = CGRect(x: cx - s*0.08, y: cy - s*0.13,
                                   width: s*0.16, height: s*0.10)
            ctx.fill(Path(ellipseIn: noseRect), with: .color(shadowCol))
            // Nose specular — single bright dot upper-left (shiny clay)
            let noseShine = CGRect(x: cx - s*0.05, y: cy - s*0.13,
                                     width: s*0.05, height: s*0.04)
            ctx.fill(Path(ellipseIn: noseShine), with: .color(shine))

            // ---- EYES ----------------------------------------------------
            let eyeY = cy - s*0.27 + size * mood.eyeSquint
            // Left eye
            let eyeRect1 = CGRect(x: cx - s*0.18, y: eyeY,
                                   width: s*0.11, height: s*0.11)
            ctx.fill(Path(ellipseIn: eyeRect1), with: .color(shadowCol))
            let eyeShine1 = CGRect(x: cx - s*0.16, y: eyeY + s*0.01,
                                    width: s*0.04, height: s*0.04)
            ctx.fill(Path(ellipseIn: eyeShine1), with: .color(shine))
            // Right eye
            let eyeRect2 = CGRect(x: cx + s*0.07, y: eyeY,
                                   width: s*0.11, height: s*0.11)
            ctx.fill(Path(ellipseIn: eyeRect2), with: .color(shadowCol))
            let eyeShine2 = CGRect(x: cx + s*0.09, y: eyeY + s*0.01,
                                    width: s*0.04, height: s*0.04)
            ctx.fill(Path(ellipseIn: eyeShine2), with: .color(shine))

            // ---- MOUTH ---------------------------------------------------
            let curve = mood.mouthCurve
            var mouth = Path()
            mouth.move(to: CGPoint(x: cx - s*0.08, y: cy - s*0.04))
            mouth.addQuadCurve(
                to: CGPoint(x: cx + s*0.08, y: cy - s*0.04),
                control: CGPoint(x: cx, y: cy - s*0.04 + s*0.07*curve)
            )
            ctx.stroke(mouth, with: .color(shadowCol), lineWidth: s*0.025)

            // ---- FEET ----------------------------------------------------
            for footX in [cx - s*0.30, cx + s*0.12] as [CGFloat] {
                let footRect = CGRect(x: footX, y: cy + s*0.36,
                                       width: s*0.18, height: s*0.10)
                // Cast shadow under each foot → into the body floor
                let footShadow = CGRect(x: footX, y: cy + s*0.40,
                                         width: s*0.18, height: s*0.05)
                ctx.fill(Path(ellipseIn: footShadow), with: .color(shadowCol.opacity(0.40)))
                // Foot base
                ctx.fill(Path(ellipseIn: footRect), with: .color(bodyDark))
                // Foot rim
                let footRim = CGRect(x: footX + s*0.01, y: cy + s*0.36,
                                      width: s*0.10, height: s*0.04)
                ctx.fill(Path(ellipseIn: footRim), with: .color(bodyLight.opacity(0.55)))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CapyScholar (replaces DuckMascot)
// A capybara holding a chunky clay flashcard. Used by the Quiz Portal
// as a friendly study-buddy presence, replacing the Phase-2 yellow
// duck which clashed with the matcha palette. Same Canvas shadings as
// CapybaraDrawing for material consistency.

struct CapyScholar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Soft halo behind
            Circle()
                .fill(VerbaTheme.glossCream)
                .frame(width: size, height: size)

            Canvas { ctx, _ in
                let s       = size
                let cx      = s / 2
                let cy      = s / 2
                let bodyColor  = VerbaTheme.clayBody
                let bodyDark   = VerbaTheme.clayBodyDark
                let bodyLight  = VerbaTheme.clayBodyLight
                let snoutColor = VerbaTheme.claySnout
                let shadowCol  = VerbaTheme.clayShadow
                let shine      = Color.white.opacity(0.92)
                let cardFill   = VerbaTheme.cardTop
                let cardBorder = VerbaTheme.oliveBorder

                // --- Cast shadow on ground -----------------------------------
                let ground = CGRect(x: cx - s*0.36, y: cy + s*0.32,
                                     width: s*0.72, height: s*0.10)
                ctx.fill(Path(ellipseIn: ground), with: .color(shadowCol.opacity(0.45)))

                // --- Flashcard (held up-and-to-the-side) --------------------
                let cardRect = CGRect(x: cx + s*0.08, y: cy - s*0.40,
                                       width: s*0.34, height: s*0.42)
                let cardShadow = CGRect(x: cx + s*0.10, y: cy - s*0.32,
                                         width: s*0.34, height: s*0.42)
                ctx.fill(Path(ellipseIn: cardShadow), with: .color(shadowCol.opacity(0.20)))
                ctx.fill(
                    Path(roundedRect: cardRect, cornerRadius: s*0.04),
                    with: .color(cardFill)
                )
                ctx.stroke(
                    Path(roundedRect: cardRect, cornerRadius: s*0.04),
                    with: .color(cardBorder),
                    lineWidth: s*0.025
                )
                // Flashcard "A:" label
                let labelPoint = CGPoint(x: cx + s*0.16, y: cy - s*0.24)
                let qmarkPoint = CGPoint(x: cx + s*0.20, y: cy - s*0.10)
                let resolvedQMark = ctx.resolve(Text("?"))
                let resolvedALabel = ctx.resolve(Text("A"))
                ctx.draw(resolvedQMark, at: qmarkPoint, anchor: .center)
                ctx.draw(resolvedALabel, at: labelPoint, anchor: .center)

                // --- Body ---------------------------------------------------
                let bodyRect = CGRect(x: cx - s*0.30, y: cy - s*0.05,
                                       width: s*0.60, height: s*0.50)
                ctx.fill(Path(ellipseIn: bodyRect), with: .color(bodyDark.opacity(0.85)))
                ctx.fill(Path(ellipseIn: bodyRect), with: .color(bodyColor))
                ctx.fill(
                    Path(ellipseIn: bodyRect),
                    with: .radialGradient(
                        Gradient(colors: [bodyColor.opacity(0.0),
                                           bodyDark.opacity(0.55)]),
                        center: CGPoint(x: cx + s*0.20, y: cy + s*0.20),
                        startRadius: s*0.10,
                        endRadius: s*0.40
                    )
                )

                // --- Head --------------------------------------------------
                let headRect = CGRect(x: cx - s*0.27, y: cy - s*0.46,
                                       width: s*0.54, height: s*0.50)
                ctx.fill(Path(ellipseIn: headRect), with: .color(bodyColor))
                ctx.fill(
                    Path(ellipseIn: headRect),
                    with: .radialGradient(
                        Gradient(colors: [bodyColor.opacity(0.0),
                                           bodyDark.opacity(0.55)]),
                        center: CGPoint(x: cx + s*0.16, y: cy - s*0.10),
                        startRadius: s*0.05,
                        endRadius: s*0.40
                    )
                )

                // --- Ears --------------------------------------------------
                for earX in [cx - s*0.27, cx + s*0.13] as [CGFloat] {
                    let earRect = CGRect(x: earX, y: cy - s*0.56,
                                          width: s*0.12, height: s*0.10)
                    ctx.fill(Path(ellipseIn: earRect), with: .color(bodyDark))
                    let earRim = CGRect(x: earX + s*0.01, y: cy - s*0.55,
                                         width: s*0.05, height: s*0.03)
                    ctx.fill(Path(ellipseIn: earRim), with: .color(bodyLight.opacity(0.65)))
                }

                // --- Snout + nose ------------------------------------------
                let snoutRect = CGRect(x: cx - s*0.16, y: cy - s*0.18,
                                        width: s*0.32, height: s*0.22)
                ctx.fill(Path(ellipseIn: snoutRect), with: .color(snoutColor))
                ctx.fill(
                    Path(ellipseIn: snoutRect),
                    with: .radialGradient(
                        Gradient(colors: [snoutColor.opacity(0.0),
                                           bodyDark.opacity(0.20)]),
                        center: CGPoint(x: cx - s*0.08, y: cy + s*0.04),
                        startRadius: s*0.02,
                        endRadius: s*0.18
                    )
                )
                let noseRect = CGRect(x: cx - s*0.07, y: cy - s*0.13,
                                       width: s*0.14, height: s*0.09)
                ctx.fill(Path(ellipseIn: noseRect), with: .color(shadowCol))
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - s*0.04, y: cy - s*0.13,
                                            width: s*0.04, height: s*0.04)),
                    with: .color(shine)
                )

                // --- Eyes (focused, studying) ------------------------------
                let eyeY = cy - s*0.27
                for (ex, mirror) in [(cx - s*0.16, false), (cx + s*0.05, false)] as [(CGFloat, Bool)] {
                    _ = mirror  // reserved for asymmetric expression variants
                    let eyeRect = CGRect(x: ex, y: eyeY,
                                           width: s*0.10, height: s*0.10)
                    ctx.fill(Path(ellipseIn: eyeRect), with: .color(shadowCol))
                    let es = CGRect(x: ex + s*0.02, y: eyeY + s*0.01,
                                     width: s*0.04, height: s*0.04)
                    ctx.fill(Path(ellipseIn: es), with: .color(shine))
                }

                // --- Mouth (small smile) -----------------------------------
                var mouth = Path()
                mouth.move(to: CGPoint(x: cx - s*0.07, y: cy - s*0.04))
                mouth.addQuadCurve(
                    to: CGPoint(x: cx + s*0.07, y: cy - s*0.04),
                    control: CGPoint(x: cx, y: cy - s*0.04 + s*0.07)
                )
                ctx.stroke(mouth, with: .color(shadowCol), lineWidth: s*0.025)

                // --- Feet --------------------------------------------------
                for footX in [cx - s*0.25, cx + s*0.07] as [CGFloat] {
                    let footRect = CGRect(x: footX, y: cy + s*0.30,
                                           width: s*0.16, height: s*0.10)
                    let footShadow = CGRect(x: footX, y: cy + s*0.34,
                                             width: s*0.16, height: s*0.05)
                    ctx.fill(Path(ellipseIn: footShadow), with: .color(shadowCol.opacity(0.40)))
                    ctx.fill(Path(ellipseIn: footRect), with: .color(bodyDark))
                    let footRim = CGRect(x: footX + s*0.01, y: cy + s*0.30,
                                          width: s*0.10, height: s*0.04)
                    ctx.fill(Path(ellipseIn: footRim), with: .color(bodyLight.opacity(0.55)))
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - DuckMascot REMOVED in Phase 6
//
// The yellow duck mascot (Phase 2) was REMOVED entirely by the Phase 6
// "cozy toy-block matte 3D" redesign. Any call site that previously
// referenced `DuckMascot` must be updated to use `CapyScholar` (the
// clay figurine replacing it) or remove the mascot from the layout
// entirely. See CapySurfersShared.swift, CapySurfersEntryView.swift,
// PaywallView.swift, and OnboardingView.swift for migration targets.

// MARK: - SnailMascot (Phase 5 — Refuel & Surf secondary mascot)
//
// 3D claymation snail rendered with the same multi-pass recipe as
// `CapybaraDrawing` and `CapyScholar`: a cast shadow plane under the
// body, a base fill, a volumetric radial gradient for directional light,
// a rim highlight on the upper-left, and a specular highlight on the
// shell apex. Used in the Quiz Portal block of CapySurfersEntryView
// and as a smaller companion next to the RefuelOverlay prompt — the
// capybara remains the primary brand identity; the snail is a secondary
// "patience / step-by-step" presence that complements the capybara's
// "energetic learner" vibe.
//
// Palette (drawn from VerbaTheme):
//   body — VerbaTheme.darkOliveInk (warm dark olive)
//   shell — VerbaTheme.amber (warm earth terracotta)
//   shell highlight — VerbaTheme.sunflower
//   shell shadow — VerbaTheme.sienna (clay-recessed groove)
struct SnailMascot: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(VerbaTheme.oliveContactShadow.opacity(0.32))
                .frame(width: size * 0.84, height: size * 0.16)
                .offset(y: size * 0.32)
                .blur(radius: 2.5)

            Canvas { ctx, _ in
                let s       = size
                let cx      = s / 2
                let cy      = s / 2
                let bodyCol   = VerbaTheme.darkOliveInk
                let bodyDark  = VerbaTheme.oliveContactShadow
                let bodyLight = VerbaTheme.glossCream
                let amber     = VerbaTheme.amber
                let amberHi   = VerbaTheme.sunflower
                let amberLo   = VerbaTheme.sienna
                let shine     = Color.white.opacity(0.92)
                let shadow    = Color.black.opacity(0.30)

                // ── Body (snail foot / base) — elongated ellipse along x-axis ──
                let bodyRect = CGRect(x: cx - s*0.42, y: cy + s*0.04,
                                       width: s*0.84, height: s*0.28)

                // Cast shadow under body
                let bodyShadow = CGRect(x: cx - s*0.42, y: cy + s*0.26,
                                         width: s*0.84, height: s*0.06)
                ctx.fill(Path(ellipseIn: bodyShadow), with: .color(shadow))
                // Body base
                ctx.fill(Path(ellipseIn: bodyRect), with: .color(bodyCol))
                // Body volumetric shading
                ctx.fill(
                    Path(ellipseIn: bodyRect),
                    with: .radialGradient(
                        Gradient(colors: [bodyCol.opacity(0.0),
                                           bodyDark.opacity(0.55)]),
                        center: CGPoint(x: cx - s*0.20, y: cy + s*0.22),
                        startRadius: s*0.05,
                        endRadius: s*0.40
                    )
                )
                // Body rim highlight (upper-right catches light)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx + s*0.12, y: cy + s*0.06,
                                            width: s*0.18, height: s*0.06)),
                    with: .color(bodyLight.opacity(0.45))
                )

                // ── Antennae (two stalks with a tip each) ──
                for (aX, aY) in [(cx - s*0.04, cy - s*0.30),
                                 (cx + s*0.08, cy - s*0.34)] {
                    // Stalk
                    ctx.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: aX, y: cy + s*0.02))
                            p.addLine(to: CGPoint(x: aX, y: aY))
                        },
                        with: .color(bodyCol),
                        style: StrokeStyle(lineWidth: s*0.025, lineCap: .round)
                    )
                    // Tip ball
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: aX - s*0.04, y: aY - s*0.04,
                                                width: s*0.08, height: s*0.08)),
                        with: .color(bodyCol)
                    )
                    // Specular on each tip
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: aX - s*0.025, y: aY - s*0.025,
                                                width: s*0.04, height: s*0.04)),
                        with: .color(shine)
                    )
                }

                // ── Shell (the silhouette-defining element) — spiral on the back ──
                let shellRect = CGRect(x: cx - s*0.18, y: cy - s*0.46,
                                        width: s*0.66, height: s*0.62)
                // Cast shadow under the shell onto the body
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - s*0.10, y: cy + s*0.06,
                                            width: s*0.50, height: s*0.06)),
                    with: .color(shadow)
                )
                // Shell base fill
                ctx.fill(Path(ellipseIn: shellRect), with: .color(amber))
                // Volumetric radial highlight on the shell (light from upper-left)
                ctx.fill(
                    Path(ellipseIn: shellRect),
                    with: .radialGradient(
                        Gradient(colors: [amberHi,
                                           amber,
                                           amberLo.opacity(0.85)]),
                        center: CGPoint(x: cx - s*0.04, y: cy - s*0.30),
                        startRadius: s*0.04,
                        endRadius: s*0.42
                    )
                )
                // Rim light at top-left of shell
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - s*0.20, y: cy - s*0.48,
                                            width: s*0.20, height: s*0.10)),
                    with: .color(amberHi.opacity(0.85))
                )
                // Spiral grooves (3 concentric amber rings for the spiral motif)
                for (r, alpha): (CGFloat, Double) in [
                    (s*0.22, 0.85),
                    (s*0.14, 0.95),
                    (s*0.07, 1.00)
                ] {
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx - r + s*0.18, y: cy - r*0.85,
                                                width: r*2, height: r*2)),
                        with: .color(amberLo.opacity(alpha)),
                        style: StrokeStyle(lineWidth: max(0.8, s*0.012), lineCap: .round)
                    )
                }
                // Specular highlight on shell apex (one bright cream dot)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx + s*0.14, y: cy - s*0.32,
                                            width: s*0.08, height: s*0.06)),
                    with: .color(shine)
                )
                // Eye (single small dark dot on the head — snails are simple)
                let eyeX = cx + s*0.20
                let eyeY = cy + s*0.04
                ctx.fill(
                    Path(ellipseIn: CGRect(x: eyeX - s*0.025, y: eyeY - s*0.025,
                                            width: s*0.05, height: s*0.05)),
                    with: .color(bodyDark)
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: eyeX - s*0.012, y: eyeY - s*0.012,
                                            width: s*0.025, height: s*0.025)),
                    with: .color(shine)
                )
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}
