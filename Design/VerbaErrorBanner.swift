import SwiftUI

// MARK: - VerbaErrorBanner
//
// THE single error surface for the app. Every error path renders this one
// component, so there is one shape, one type treatment and one tone across
// the whole product instead of three ad-hoc alert strings.
//
// Design notes, deliberately inheriting the established VerbaDoc idiom
// rather than inventing a new one for errors:
//
//   • Tinted flat surface + a 2pt `oliveBorder` stroke + a HARD offset
//     shadow (`radius: 0, y: 6`). This is the same "sticker" treatment the
//     study guide and the rationale overlay use, so the banner reads as
//     part of the app.
//   • No gradient, no `.ultraThinMaterial` glass, no emoji. The icon is an
//     SF Symbol chosen by `ErrorKind`, never a character.
//   • Colour is used ONCE per banner — one accent for the icon and the
//     retry label — because the discipline this app already follows is one
//     accent, one meaning. Green never appears here: green means mastery.
//
// Usage:
//
//     .errorBanner(presentation: vm.error)              // passive
//     .errorBanner(presentation: vm.error, onRetry: { }) // with retry
//
// Build the presentation with `ErrorPresentation(error, in: .aiGeneration)`
// so the copy stays owned by `FriendlyErrorMapper`.

struct VerbaErrorBanner: View {

    let presentation: ErrorPresentation

    /// Omit to hide the retry affordance. Also suppressed automatically for
    /// kinds where retrying is dishonest (see `isRetryable`).
    var onRetry: (() -> Void)?

    /// Omit to keep the banner dismiss-free (the right default inside a
    /// form or an inline section).
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            Image(systemName: presentation.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(presentation.kind.tone)
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.message)
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.recoveryHint)
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if let onRetry, presentation.isRetryable {
                    Button(action: onRetry) {
                        Text("retry")
                            .font(VerbaFont.syne(.bold, size: 11))
                            .tracking(0.6)
                            .foregroundStyle(presentation.kind.tone)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(presentation.kind.tone, lineWidth: 1.5)
                            )
                    }
                    // Explicit style + colour on purpose: a default-styled
                    // Button inherits the global accent, which is how
                    // "Surf Now" and "Shop" ended up rendering system blue.
                    .buttonStyle(.plain)
                    .accessibilityLabel("Try again")
                }

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VerbaTheme.muted)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .padding(14)
        .background(VerbaTheme.glossCream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                radius: 0, x: 0, y: 6)
        // Announce the whole thing as one element so VoiceOver reads the
        // message + hint together instead of four separate fragments.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Visual mapping
//
// Both the icon and the tone live here rather than in ErrorPresentation.swift,
// so ALL visual choices for an error sit in one file. `kind` is the seam
// between "what went wrong" (Foundation side) and "how it looks" (design side).

extension ErrorKind {

    /// SF Symbol name. Symbols only — emoji are banned in the shipped UI.
    var symbol: String {
        switch self {
        case .offline:       return "wifi.slash"
        case .network:       return "arrow.clockwise"
        case .rateLimited:   return "hourglass"
        case .server:        return "exclamationmark.triangle.fill"
        case .auth:          return "lock.fill"
        case .configuration: return "gearshape.fill"
        case .ai:            return "sparkles"
        case .unknown:       return "exclamationmark.circle.fill"
        }
    }

    /// The ONE accent this banner is allowed to use.
    ///
    /// `danger` is reserved for things the user must act on (a bad session,
    /// or our server breaking). Transient, retryable problems get `orange` so
    /// they don't read as catastrophic. Build-configuration failures get
    /// `muted` because they are not the user's fault and not fixable by them —
    /// alarming them would be misleading. Nothing here ever uses `green`,
    /// which this app reserves for mastery and progress.
    var tone: Color {
        switch self {
        case .auth, .server:                        return VerbaTheme.danger
        case .offline, .network, .rateLimited, .ai: return VerbaTheme.orange
        case .configuration, .unknown:              return VerbaTheme.muted
        }
    }
}

// MARK: - Convenience modifier

extension View {

    /// Attach the standard error banner above this view.
    ///
    /// Pass `nil` to render nothing, so call sites can bind a single
    /// optional error value without an `if` in every body:
    ///
    ///     .errorBanner(presentation: viewModel.error, onRetry: viewModel.reload)
    func errorBanner(
        presentation: ErrorPresentation?,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        // `overlay`, NOT a VStack wrapper. Wrapping the host changes ITS
        // layout — it breaks List/ScrollView scrolling and can defeat
        // `.ignoresSafeArea()` on a full-bleed screen. An overlay adds the
        // banner and leaves the host's own layout completely untouched.
        overlay(alignment: .top) {
            // The `Group` + `.animation` pair is load-bearing: `.transition`
            // only animates its insertion when the animation is attached to
            // an ANCESTOR of the conditional, not to the conditional's own
            // child. Putting it on the banner itself silently drops the
            // insert animation. Wrapping in a Group keeps it off the host,
            // so the host still isn't re-animated.
            Group {
                if let presentation {
                    VerbaErrorBanner(
                        presentation: presentation,
                        onRetry: onRetry,
                        onDismiss: onDismiss
                    )
                    .padding(.horizontal, 20)
                    // `safeAreaPadding`, not a bare top padding: most
                    // VerbaDoc screens are full-bleed (`VerbaTheme.bg
                    // .ignoresSafeArea()`), so this overlay inherits the
                    // EXPANDED bounds and a fixed 8pt would tuck the banner
                    // under the status bar / Dynamic Island. Requires iOS
                    // 17, which this project already targets.
                    .safeAreaPadding(.top)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: presentation)
        }
    }
}

// MARK: - Preview

#Preview("Error banner") {
    ZStack {
        VerbaTheme.bg.ignoresSafeArea()
        VStack(spacing: 16) {
            VerbaErrorBanner(
                presentation: ErrorPresentation(
                    message: "The AI service is rate limited. Try again in about 8 seconds.",
                    kind: .rateLimited
                ),
                onRetry: {},
                onDismiss: {}
            )
            VerbaErrorBanner(
                presentation: ErrorPresentation(
                    message: "Something went wrong. Try again in a moment.",
                    kind: .auth
                ),
                onRetry: {},
                onDismiss: {}
            )
            VerbaErrorBanner(
                presentation: ErrorPresentation(
                    message: "Couldn't open local storage. Please reinstall VerbaDoc.",
                    kind: .server
                ),
                onRetry: {},
                onDismiss: nil
            )
        }
        .padding(.vertical, 24)
    }
}
