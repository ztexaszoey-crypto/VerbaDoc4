import Foundation

// MARK: - ErrorPresentation
//
// The ONE user-facing error surface.
//
// The problem this exists to fix: three competing generic strings were
// showing up in different screens — "No connection.", "Couldn't reach the
// server.", "AI generation hit a snag." — with no way to tell from the
// outside which component produced which. That is precisely why the
// failures were so hard to diagnose.
//
// ── Division of labour (deliberate) ────────────────────────────────────
//
//   • `FriendlyErrorMapper` remains the SINGLE source of user-facing copy
//     for everything it knows about. No string from it is duplicated here.
//
//   • The two AI error types are the one exception, and it is a narrow,
//     GATED one: the mapper does not know they exist (see below), so it
//     answers with "AI generation hit a snag" for a rate limit, a retired
//     model ID, AND total provider failure alike. For the kinds a user can
//     actually act on (rate limit, server, network, AI) this type prefers
//     their key-free `errorDescription` — that is where "rate limited, try
//     again in about 8 seconds" comes from. For configuration and auth it
//     deliberately does NOT, because that copy names vendors and build
//     files.
//
//   • Auth and offline errors route to the mapper. A build-configuration
//     failure does NOT: it has its own neutral sentence, because the
//     mapper's `.aiGeneration` fallback copy ends in an upsell
//     ("...or upgrade for priority") that no purchase can satisfy.
//
//   • This type adds the CLASSIFICATION the mapper throws away: the
//     `kind`. The banner uses `kind` to pick an icon, an accent, and a
//     recovery hint. Visual mapping lives with the presentation (see
//     `ErrorKind`'s extension in VerbaErrorBanner.swift).
//
// ── Why the AI types need this at all ──────────────────────────────────
//
// `AIChatError` and `NVIDIAError` are not `AuthService.AuthError`, so every
// domain branch in `FriendlyErrorMapper.message(for:in:)` misses them and
// they fall through to `context.defaultMessage`. Worse, that fallthrough is
// reachable from FOUR places — the final `return`, plus `mapURLError`'s
// `default:`, plus `mapCocoaError`'s and `mapPOSIXError`'s `default:` — so
// seeing the generic string tells you almost nothing about the cause.
//
// This is also why the consolidation must not become a second `AppError`
// enum carrying its own copy: that would drift from the mapper within a
// week. Classification only, never copy.

// MARK: - Kind

/// What actually went wrong. Drives the banner's icon, tone and recovery
/// hint — and nothing else.
enum ErrorKind: String, Sendable {
    /// Genuinely no connectivity. The only case where blaming the user's
    /// connection is honest.
    case offline

    /// Reachable-ish, but the request failed in transit.
    case network

    /// 429. Distinct from `server` because the correct user action differs:
    /// wait briefly and retry, rather than reporting a bug.
    case rateLimited

    /// 5xx, a malformed response, an ATS/TLS block, or an unavailable
    /// model ID. All of these are OUR side, not the user's connection.
    case server

    /// Credentials or session. The user CAN act on this — sign in again.
    case auth

    /// A build/configuration problem: no provider key, a missing or still
    /// placeholder key, or a key the provider rejected. Kept separate from
    /// `auth` on purpose — "sign out and back in" cannot rotate an API key,
    /// and telling a user to do something that cannot work is the exact
    /// failure mode this whole surface exists to remove.
    case configuration

    /// An AI provider failed for a non-network reason (empty or malformed
    /// reply, every provider exhausted).
    case ai

    case unknown
}

// MARK: - Presentation

/// Everything a view needs to render one error, and nothing more.
struct ErrorPresentation: Equatable, Sendable {

    let message: String
    let kind: ErrorKind

    /// The user's message says what happened; this says what to do about it.
    /// Without it the banner is just an apology.
    var recoveryHint: String {
        switch kind {
        case .offline:       return "Check your connection, then try again."
        case .network:       return "Check your connection, then try again."
        case .rateLimited:   return "Give it a few seconds, then try again."
        case .server:        return "This one's on us — try again in a moment."
        case .auth:          return "Sign out and back in, then try again."
        case .configuration: return "AI isn't set up in this build."
        case .ai:            return "Try again. If it keeps failing, try a shorter document."
        case .unknown:       return "Try again, or restart the app."
        }
    }

    /// Whether offering a "retry" affordance is honest. Retrying a rejected
    /// key or an expired session just fails again, so those say so instead.
    var isRetryable: Bool {
        switch kind {
        case .offline, .network, .rateLimited, .server, .ai: return true
        case .auth, .configuration, .unknown:                return false
        }
    }

    // MARK: Factory

    /// Build the presentation for a thrown error.
    ///
    /// - Parameter context: passed straight through to the mapper, so its
    ///   fallback copy stays specific to what the user just attempted.
    init(_ error: Error, in context: FriendlyErrorMapper.Context) {
        let kind     = Self.kind(for: error)
        self.kind    = kind
        self.message = Self.message(for: error, in: context, kind: kind)
    }

    /// Direct construction, for cases where the caller already knows.
    init(message: String, kind: ErrorKind) {
        self.message = message
        self.kind    = kind
    }

    // MARK: Copy

    /// Prefers our own AI error copy, but ONLY for the kinds a user can act
    /// on. Falls through to the mapper otherwise.
    ///
    /// The gate matters. `AIChatError.errorDescription` cannot leak a key —
    /// it was written to be key-free — but its **configuration** cases are
    /// build-facing copy: `.missingKey` says "Groq's API key isn't
    /// configured. Add it to Config.xcconfig." and `.unauthorized` says
    /// "Check Config.xcconfig." Shipping that to a real user is worse than
    /// the mapper's generic sentence, and it contradicts the `.configuration`
    /// recovery hint that sits next to it. So configuration and auth keep
    /// the mapper's neutral wording; a user can neither add a key nor
    /// rotate one.
    ///
    /// For the kinds they CAN act on, the provider copy is strictly better:
    /// "The AI service is rate limited. Try again in about 8 seconds."
    private static func message(
        for error: Error,
        in context: FriendlyErrorMapper.Context,
        kind: ErrorKind
    ) -> String {
        switch kind {
        case .rateLimited, .server, .network, .ai, .unknown:
            if let ai = error as? AIChatError, let desc = ai.errorDescription {
                return desc
            }
            if let nim = error as? NVIDIAError, let desc = nim.errorDescription {
                return desc
            }
        case .configuration:
            // Explicitly NOT the mapper's fallback. `.aiGeneration`'s
            // default message ends with "or upgrade for priority" — an
            // upsell prompt for a missing API key, which no purchase can
            // fix, sitting next to a hint that says "AI isn't set up in
            // this build." Configuration failures get neutral, honest copy.
            return "AI isn't available in this build right now."
        case .auth, .offline:
            break
        }
        // Everything else: the mapper owns the string. One place, as before.
        return FriendlyErrorMapper.message(for: error, in: context)
    }

    // MARK: Classification

    /// Maps the error to a kind. Copy is NOT produced here.
    ///
    /// Order matters: the AI error types are checked first because they are
    /// the ones the mapper cannot see, and their `NSError` bridging produces
    /// a module-scoped domain that no domain check below would match.
    private static func kind(for error: Error) -> ErrorKind {

        // 1. Multi-provider AI router.
        if let ai = error as? AIChatError {
            switch ai {
            case .noProviderConfigured, .missingKey, .unauthorized:
                // Build configuration — the user cannot fix these, so they
                // must not be classified as `.auth`.
                return .configuration
            case .rateLimited:
                return .rateLimited
            case .serverError, .badRequest:
                return .server
            case .networkError:
                return .network
            case .invalidResponse, .emptyResponse, .allProvidersFailed:
                return .ai
            }
        }

        // 2. The NVIDIA NIM transport, which still reports its own taxonomy
        //    to its direct callers (the embedding client).
        if let nim = error as? NVIDIAError {
            switch nim {
            case .missingAPIKey, .unauthorized:
                return .configuration
            case .rateLimited:
                return .rateLimited
            case .badRequest, .httpError:
                return .server
            case .networkError:
                return .network
            case .invalidResponse:
                return .ai
            }
        }

        // 3. Auth already has its own user-facing copy, and it is only ever
        //    an auth problem the user can act on.
        if error is AuthService.AuthError { return .auth }

        // 4. Everything else: classify by domain + code. This is the only
        //    place we inspect raw codes, and we re-derive rather than
        //    reading the mapper's string so the mapper stays free to change
        //    its wording without breaking styling.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,          // -1009
                 NSURLErrorNetworkConnectionLost,            // -1005
                 NSURLErrorDataNotAllowed:                   // -1020
                return .offline

            case NSURLErrorTimedOut:                         // -1001
                return .network

            case NSURLErrorUserAuthenticationRequired,       // -1013
                 NSURLErrorUserCancelledAuthentication:      // -1012
                return .auth

            case NSURLErrorCannotFindHost,                   // -1003
                 NSURLErrorCannotConnectToHost,              // -1004
                 NSURLErrorDNSLookupFailed,                  // -1006
                 NSURLErrorHTTPTooManyRedirects,             // -1007
                 NSURLErrorRedirectToNonExistentLocation,    // -1010
                 NSURLErrorBadServerResponse,                // -1011
                 NSURLErrorCannotParseResponse,              // -1017
                 NSURLErrorAppTransportSecurityRequiresSecureConnection: // -1022
                // Host / DNS / TLS / ATS / malformed-response failures.
                // NOT the user's connection — which is why these must never
                // render as "No connection."
                return .server

            default:
                return .network
            }
        }

        return .unknown
    }
}
