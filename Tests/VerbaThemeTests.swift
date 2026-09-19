import SwiftUI
import UIKit

// XCTest is unavailable inside the VerbaDoc main app target; guard
// the symbol-using class body behind canImport so the file parses
// anywhere. When Tests/ is later wired into an XCTest target, the
// guard compiles in and the regression suite activates without
// any other change required here.
#if canImport(XCTest)
import XCTest
#endif

// MARK: - VerbaThemeTests
//
// LEGACY TOKEN ALIASING REGRESSION TESTS
// ---------------------------------------
// The FELIwS migration strategy pinned the Phase-0 / legacy token
// values in `VerbaTheme.swift` to their Phase-2 / FELIwS palette
// twins so that every existing call site (LibraryView,
// DocumentDetailView, FlashcardStudyView, OpenAnswerView,
// ExamModeView, StudyGuideView, CapySurfersGameView,
// CapySurfersResultsView, PracticeModePickerView, UploadTabView,
// PaywallView — and hundreds of helper views) instantly inherits
// the pastel-green look without any code change.
//
// These tests pin the aliases. If a future developer changes ONE of
// the Phase-2 twins (e.g. decides "let's make `bgTop` slightly more
// saturated") WITHOUT updating the matching legacy alias, every
// legacy screen will visibly drift away from the FELIwS design. The
// tests below fail loudly in that scenario.
//
// Place this file under a future Tests target when you wire up an
// XCTest target in project.pbxproj. The body is self-contained against
// the production code: it does NOT import anything beyond SwiftUI
// + XCTest.

// MARK: - Test class -- active only when XCTest is linked
#if canImport(XCTest)

final class VerbaThemeTests: XCTestCase {

    // Tolerance for floating-point `.red/.green/.blue` comparison. The
    // Phase-2 tokens are defined as 3-decimal RGB triples so equality
    // should hold within machine epsilon; 0.001 is a generous safety
    // margin against future rounding changes.
    private let tolerance: Double = 0.001

    // MARK: - Helpers

    /// Resolve a SwiftUI `Color` to its RGBA components.
    ///
    /// We use `UIGraphicsImageRenderer` (instead of SwiftUI's
    /// `ImageRenderer`) for ONE REASON: byte-order determinism.
    /// `UIGraphicsImageRenderer` is documented by Apple to emit
    /// `kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big`
    /// — meaning the resulting CGImage pixel buffer is RGBA8 with
    /// `bytes[0]=R, bytes[1]=G, bytes[2]=B, bytes[3]=A`.
    ///
    /// The original implementation used `ImageRenderer.cgImage` and
    /// read `bytes[0..3]` as if RGBA, but `SwiftUI.ImageRenderer` on
    /// iOS little-endian actually emits BGRA, so the R and B channels
    /// were silently swapped. Color-equality tests still passed (both
    /// sides got swapped identically) but raw channel assertions
    /// (`c.g >= c.b - 0.10`, the shadow regression thresholds) read
    /// the wrong channels and would have produced silent false passes
    /// on a regression that genuinely flipped shadow() back to black.
    /// Switching to `UIGraphicsImageRenderer` removes that ambiguity.
    ///
    /// Notes:
    ///   * `CGImage.dataProvider.data` is occasionally nil on
    ///     simulator render edge cases — we fail loudly with
    ///     `XCTFail` rather than silently returning zeros, so the
    ///     regression cannot mask a palette decoupling.
    ///   * `UIColor(color)` reads the SwiftUI Color components and
    ///     converts them to sRGB at display. For named colours whose
    ///     SwiftUI definition diverges from UIKit's (e.g. `.system
    ///     colors`), prefer the explicitly-defined RGBA tokens.
    private func rgba(_ color: Color, file: StaticString = #file, line: UInt = #line) -> (r: Double, g: Double, b: Double, a: Double) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 4, height: 4),
            format: format
        )
        let img = renderer.image { ctx in
            UIColor(color).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        guard let cg = img.cgImage,
              let provider = cg.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else {
            XCTFail("UIGraphicsImageRenderer failed to produce CGImage for color — render path is broken",
                    file: file, line: line)
            return (0, 0, 0, 0)
        }
        // UIGraphicsImageRenderer emits RGBA8 byte order (verified by
        // Apple's documentation on kCGImageAlphaPremultipliedLast |
        // kCGBitmapByteOrder32Big). bytes[0..3] = R, G, B, A.
        // We sample the first pixel; with opaque=true and scale=1 the
        // entire 4x4 buffer is identical.
        let r = Double(ptr[0]) / 255.0
        let g = Double(ptr[1]) / 255.0
        let b = Double(ptr[2]) / 255.0
        let a = Double(ptr[3]) / 255.0
        return (r, g, b, a)
    }

    /// Single self-check: confirm the `rgba()` helper reads channels
    /// in the order it's documented to. If Apple ever changes
    /// `UIGraphicsImageRenderer`'s byte order, this test will fail
    /// BEFORE any production test runs and loudly reveal the swap.
    ///
    /// We probe SEVEN synthetic fingerprints — the four pure primaries
    /// (R,G,B) AND the three secondaries (Y,C,M) where TWO distinct
    /// channels are non-zero. The three primaries alone would let an
    /// R↔G swap or a G↔B swap survive the byte-order check. The
    /// secondaries catch those. Every fingerprint is an explicit
    /// `Color(red:green:blue:opacity:)` literal so we don't depend
    /// on Apple's system colors (which could shift in future iOS
    /// versions, e.g. display-P3 systemRed).
    func testRgbaHelper_byteOrder_isRgbaNotBgra() {
        let fingerprints: [(String, Double, Double, Double)] = [
            ("pure R",        1.0, 0.0, 0.0),
            ("pure G",        0.0, 1.0, 0.0),
            ("pure B",        0.0, 0.0, 1.0),
            ("yellow R+G",    1.0, 1.0, 0.0),
            ("cyan G+B",      0.0, 1.0, 1.0),
            ("magenta R+B",   1.0, 0.0, 1.0),
            ("white all",     1.0, 1.0, 1.0),
        ]
        for (name, expectedR, expectedG, expectedB) in fingerprints {
            let color = Color(red: expectedR, green: expectedG, blue: expectedB, opacity: 1)
            let c = rgba(color)
            XCTAssertEqual(c.r, expectedR, accuracy: 0.001,
                "\(name): R channel expected \(expectedR), got \(c.r) — byte order may be swapped")
            XCTAssertEqual(c.g, expectedG, accuracy: 0.001,
                "\(name): G channel expected \(expectedG), got \(c.g) — byte order may be swapped")
            XCTAssertEqual(c.b, expectedB, accuracy: 0.001,
                "\(name): B channel expected \(expectedB), got \(c.b) — byte order may be swapped")
            XCTAssertEqual(c.a, 1.0, accuracy: 0.001,
                "\(name): A channel expected 1.0, got \(c.a)")
        }
    }

    private func XCTAssertColorsEqual(
        _ lhs: Color, _ rhs: Color,
        _ message: String = "",
        file: StaticString = #file, line: UInt = #line
    ) {
        let l = rgba(lhs, file: file, line: line)
        let r = rgba(rhs, file: file, line: line)
        XCTAssertEqual(l.r, r.r, accuracy: tolerance, "R channel differs — \(message)", file: file, line: line)
        XCTAssertEqual(l.g, r.g, accuracy: tolerance, "G channel differs — \(message)", file: file, line: line)
        XCTAssertEqual(l.b, r.b, accuracy: tolerance, "B channel differs — \(message)", file: file, line: line)
        XCTAssertEqual(l.a, r.a, accuracy: tolerance, "A channel differs — \(message)", file: file, line: line)
    }

    // MARK: - Phase-0 / Phase-2 alias parity

    /// bg  ↔ bgTop    (#EEF7D5 cream-yellow backdrop top)
    func testLegacyBg_aliasedToBgTop() {
        XCTAssertColorsEqual(VerbaTheme.bg, VerbaTheme.bgTop,
                             "VerbaTheme.bg must match VerbaTheme.bgTop")
    }

    /// card ↔ cardTop (#D8F08D sticky-note top fill)
    func testLegacyCard_aliasedToCardTop() {
        XCTAssertColorsEqual(VerbaTheme.card, VerbaTheme.cardTop,
                             "VerbaTheme.card must match VerbaTheme.cardTop")
    }

    /// cream ↔ bgMid  (#E7F4CB cream mid-stop)
    func testLegacyCream_aliasedToBgMid() {
        XCTAssertColorsEqual(VerbaTheme.cream, VerbaTheme.bgMid,
                             "VerbaTheme.cream must match VerbaTheme.bgMid")
    }

    /// ink  ↔ darkOliveInk (#293317 dark olive body ink)
    func testLegacyInk_aliasedToDarkOliveInk() {
        XCTAssertColorsEqual(VerbaTheme.ink, VerbaTheme.darkOliveInk,
                             "VerbaTheme.ink must match VerbaTheme.darkOliveInk")
    }

    /// muted ↔ mediumOliveMuted (#697A4A medium olive muted)
    func testLegacyMuted_aliasedToMediumOliveMuted() {
        XCTAssertColorsEqual(VerbaTheme.muted, VerbaTheme.mediumOliveMuted,
                             "VerbaTheme.muted must match VerbaTheme.mediumOliveMuted")
    }

    /// border ↔ oliveBorder (#556B2F dark olive primary outline)
    func testLegacyBorder_aliasedToOliveBorder() {
        XCTAssertColorsEqual(VerbaTheme.border, VerbaTheme.oliveBorder,
                             "VerbaTheme.border must match VerbaTheme.oliveBorder")
    }

    /// green ↔ ctaTop (#A8D63C primary mint CTA top)
    func testLegacyGreen_aliasedToCtaTop() {
        XCTAssertColorsEqual(VerbaTheme.green, VerbaTheme.ctaTop,
                             "VerbaTheme.green must match VerbaTheme.ctaTop")
    }

    /// yellow ↔ flowerGold (#FFD700 yellow XP / capy-flower accent)
    func testLegacyYellow_aliasedToFlowerGold() {
        XCTAssertColorsEqual(VerbaTheme.yellow, VerbaTheme.flowerGold,
                             "VerbaTheme.yellow must match VerbaTheme.flowerGold")
    }

    // MARK: - Shadow helper resolves to olive contact shadow

    /// (Historical note) The previous threshold-based shadow test
    /// (`testShadow_opacity_isWarmOliveNotColdBlack`) was REMOVED in
    /// favour of the equivalence test below. The threshold test
    /// asserted `c.r > 0.18 / g > 0.20 / b > 0.10` at three opacities,
    /// but under the helper's `format.opaque = true` config the
    /// renderer composites EVERY swatch over its white backing, so
    /// both olive (target) AND black (regression) at opacity 0.10
    /// produce ≈(0.92, 0.93, 0.91) and ≈(0.90, 0.90, 0.90)
    /// respectively. Both pass the loose thresholds. The test name
    /// claimed "warm olive not cold black" but the assertion could
    /// not actually distinguish them. The equivalence test below is
    /// the strictly-correct regression.

    // MARK: - Status colors intentionally distinct from matcha

    /// FELIwS brief explicitly excludes saturation clashes in the
    /// primary palette. Orange / danger / brown are status-channel
    /// colours and SHOULD differ from `ctaTop` / `oliveBorder` /
    /// `darkOliveInk` so they read as alarms, not decoration.
    func testOrange_distinctFromMatchaCta() {
        let orange = rgba(VerbaTheme.orange)
        let cta    = rgba(VerbaTheme.ctaTop)
        XCTAssertGreaterThan(abs(orange.r - cta.r), 0.05,
                             "VerbaTheme.orange must visually differ from ctaTop")
    }

    func testDanger_distinctFromMatchaCta() {
        let danger = rgba(VerbaTheme.danger)
        let cta    = rgba(VerbaTheme.ctaTop)
        XCTAssertGreaterThan(abs(danger.r - cta.r), 0.10,
                             "VerbaTheme.danger must visually differ from ctaTop")
    }

    /// Cocoa brown (used by document-card icon tint) is intentionally
    /// a warm earth-tone, NOT an FELIwS matcha. Lock it down so a
    /// future "let's align everything" mistake doesn't paint
    /// document-card icons in pastel green.
    func testBrown_distinctFromMatchaCtaAndOliveBorder() {
        let brown      = rgba(VerbaTheme.brown)
        let cta        = rgba(VerbaTheme.ctaTop)
        let olive      = rgba(VerbaTheme.oliveBorder)
        XCTAssertGreaterThan(abs(brown.r - cta.r),    0.20,
                             "VerbaTheme.brown must visually differ from ctaTop")
        XCTAssertGreaterThan(abs(brown.r - olive.r), 0.15,
                             "VerbaTheme.brown must visually differ from oliveBorder")
        // brown should also be a clearly RED-shifted earth tone
        // (R > G > B), not a green shift.
        XCTAssertGreaterThan(brown.r - brown.b, 0.10,
                             "VerbaTheme.brown should be warm earth-tone (R > B)")
    }

    // MARK: - Design-system surface remains pastel/green-only

    /// Sanity: the primary palette ladder does NOT show purple
    /// contamination (purple has B > R with significant margin).
    /// We assert the SIGNED difference r - b is NOT significantly
    /// negative — i.e. R is NOT significantly smaller than B.
    ///
    /// Note: We deliberately do NOT cap absolute B magnitude.
    /// Cream-yellow tones (`bgTop`, `bgMid`, `glossCream`) legitimately
    /// carry a strong blue component (≈0.80 in sRGB) — capping B at
    /// any threshold < 0.85 would falsely fail those probes. The
    /// TRUE differentiator between cream/yellow/green (FELIwS palette)
    /// and purple/blue (forbidden) is the SIGN of (R - B):
    ///   * cream/yellow/green → R - B ≥ 0 (warm)
    ///   * purple/blue        → R - B << 0 (cool)
    /// so a single `r - b > -0.30` assertion is sufficient.
    ///
    /// History: the previous version had TWO assertions: a flawed
    /// `c.b ≤ 0.65` cap (false-failed on legitimate cream tones) AND
    /// the r-b assertion with the sign flipped (would have
    /// false-failed on every green and yellow probe). Both have
    /// been corrected.
    func testFELIwSPalette_noPurpleContamination() {
        let probes: [(String, Color)] = [
            ("bgTop",            VerbaTheme.bgTop),
            ("bgMid",            VerbaTheme.bgMid),
            ("bgBottom",         VerbaTheme.bgBottom),
            ("cardTop",          VerbaTheme.cardTop),
            ("cardMid",          VerbaTheme.cardMid),
            ("cardBottom",       VerbaTheme.cardBottom),
            ("ctaTop",           VerbaTheme.ctaTop),
            ("ctaBottom",        VerbaTheme.ctaBottom),
            ("glossCream",       VerbaTheme.glossCream),
            ("flowerGold",       VerbaTheme.flowerGold),
            ("mint",             VerbaTheme.mint),
            ("sage",             VerbaTheme.sage),
            ("pistachio",        VerbaTheme.pistachio),
            ("darkOliveInk",     VerbaTheme.darkOliveInk),
            ("mediumOliveMuted", VerbaTheme.mediumOliveMuted),
        ]
        for (name, color) in probes {
            let c = rgba(color)
            // Purple signature: B significantly > R. Reject when
            // (r - b) is significantly negative.
            XCTAssertGreaterThan(c.r - c.b, -0.30,
                "\(name) shows purple contamination (r-b=\(c.r - c.b))")
        }
    }

    // MARK: - Shadow helper resolves to olive contact shadow

    /// semantic-equivalence test: `shadow(α)` MUST render identically
    /// to `oliveContactShadow.opacity(α)` at every opacity we use.
    ///
    /// This is the *correct* regression for the migration's biggest
    /// visual guarantee: pastel cards / buttons must NOT feel cold.
    /// The previous threshold-based test (`r > 0.18`, etc.) was
    /// silently mis-calibrated under `format.opaque = true` because
    /// the UIGraphicsImageRenderer's opaque white backing composites
    /// BOTH olive AND black sources to ≈(0.90, 0.90, 0.90 at low
    /// opacities), so the loose thresholds let a black fallback pass.
    ///
    /// Comparing shadow(α) against the *intended* source
    /// `oliveContactShadow.opacity(α)` as two independent draws is
    /// tight: if shadow() falls through to ANY different colour
    /// (black, white, navy, etc.), the equality breaks. We sample
    /// three representative opacities.
    func testShadow_forwardsIdenticalRGBA_to_oliveContactShadow() {
        let opacities: [Double] = [0.10, 0.30, 0.50]
        for alpha in opacities {
            XCTAssertColorsEqual(
                VerbaTheme.shadow(alpha),
                VerbaTheme.oliveContactShadow.opacity(alpha),
                "shadow(\(alpha)) must be byte-identical to oliveContactShadow.opacity(\(alpha))")
        }
    }

    /// Note on edge cases (intentionally removed):
    /// `testShadow_opacityZero_isFullyTransparent` from a prior draft
    /// could NOT pass under the helper's `format.opaque = true` config
    /// because opaque rendering composites zero-alpha swatches over
    /// the white backing (giving (1,1,1,1), not (0,0,0,0)). The
    /// three-channel shadow regression above already detects any
    /// future regression that drops `shadow()` back to a black
    /// source colour — which was the only meaningful defect this
    /// category could surface. Keep the simpler, more reliable
    /// three-channel check; do not re-introduce the opacity-zero
    /// test without first switching `format.opaque = false` AND
    /// re-calibrating every shadow regression threshold.

    /// Sanity: the palette ladder should hold SOME warmth in the R
    /// channel (cream/yellow/green) — none should be a cold blue.
    /// Probe FIVE random sample points to ensure every named color is
    /// warm, not blue.
    func testFELIwSPalette_isWarmNotColdBlue() {
        let probes: [(String, Color)] = [
            ("bgTop", VerbaTheme.bgTop),
            ("glossCream", VerbaTheme.glossCream),
            ("ctaTop", VerbaTheme.ctaTop),
            ("oliveBorder", VerbaTheme.oliveBorder),
            ("darkOliveInk", VerbaTheme.darkOliveInk),
        ]
        for (_, color) in probes {
            let c = rgba(color)
            // Cream/yellow/green all have G >= B (greens invert minutely
            // with mint/sage, but never blue-dominant).
            XCTAssertGreaterThanOrEqual(c.g, c.b - 0.10,
                "FELIwS colour unexpectedly blue-dominant (g=\(c.g), b=\(c.b))")
        }
    }

    // MARK: - Radii ladder

    /// Legacy Phase-0 radii (8 / 12 / 16 / 20) are referenced by
    /// hundreds of un-migrated call sites — they MUST persist.
    func testLegacyRadiiLadder_persists() {
        XCTAssertEqual(VerbaTheme.r8,  8)
        XCTAssertEqual(VerbaTheme.r12, 12)
        XCTAssertEqual(VerbaTheme.r16, 16)
        XCTAssertEqual(VerbaTheme.r20, 20)
    }

    /// Phase-2 chunky radii (24 / 28 / 30) are referenced by the
    /// pastel button / card chassis. They MUST exist so hand-written
    /// pill buttons / sticky-note cards continue to compile.
    func testChunkyRadiiLadder_inPhase2() {
        XCTAssertEqual(VerbaTheme.r24, 24)
        XCTAssertEqual(VerbaTheme.r28, 28)
        XCTAssertGreaterThanOrEqual(VerbaTheme.r30, 30)
    }

    // MARK: - Gradient symbols build

    /// The four LinearGradient / RadialGradient symbols are baked
    /// into PastelBackdrop, PastelCardStyle, pastel.button styles, etc.
    /// Just touching them here is enough — if any of these is renamed
    /// / removed, the entire FCS redesign compiles-fails. Pin the
    /// surface so a future cleanup doesn't silently drop them.
    func testGradientSymbols_compileAndResolve() {
        let _: LinearGradient = VerbaTheme.creamGradient
        let _: LinearGradient = VerbaTheme.stickyNote
        let _: LinearGradient = VerbaTheme.primaryCta
        let _: RadialGradient = VerbaTheme.cornerShine
    }

} // end final class VerbaThemeTests

#endif // canImport(XCTest)

