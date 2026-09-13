import Foundation

// MARK: - NIMCore
//
// Shared plumbing for the AI providers in VerbaDoc. The NVIDIA NIM
// clients (NVIDIAAIService chat completions, NIMEmbeddingService
// retrieval embeddings) and the multi-provider AIChatRouter all sit on
// top of these types, so the security-critical key handling exists in
// exactly ONE place and can never drift between callers.
//
//   • APIKey        — reads ANY provider key from the Info.plist.
//   • NVIDIAAPIKey  — the NVIDIA-named entry point onto APIKey.
//   • NVIDIAError   — the transport's error taxonomy.
//   • NIMHTTP       — transport: timeouts, cancellation passthrough,
//                     HTTP status mapping, bounded retry on 429/5xx.
//
// Key security contract (non-negotiable):
//   • The key is read from the Info.plist value `NVIDIA_API_KEY`, which
//     is injected at build time from the gitignored Config.xcconfig
//     (`INFOPLIST_KEY_NVIDIA_API_KEY = $(NVIDIA_API_KEY)`).
//   • The key is NEVER hardcoded, NEVER logged, and NEVER included in
//     an error description or thrown value.
//
// Endpoint: https://integrate.api.nvidia.com/v1 — OpenAI-compatible,
// so the request/response shapes mirror OpenAI's REST API.

// MARK: - Errors

/// The single error taxonomy for NVIDIA NIM calls.
///
/// Every `errorDescription` is user-safe: none of them can contain the
/// API key, the request body, or a raw server payload.
enum NVIDIAError: LocalizedError {

    /// No `NVIDIA_API_KEY` in the Info.plist, or it still holds the
    /// placeholder value from the setup instructions.
    case missingAPIKey

    /// 401 / 403 — the key was rejected (rotated, revoked, or typo'd).
    case unauthorized

    /// The request never reached the server (offline, DNS, TLS).
    case networkError

    /// 400 / 404 / 422 — the request itself was rejected. In practice
    /// this almost always means the configured model ID (or a request
    /// parameter) isn't available on the catalog; NVIDIA adds and
    /// retires model IDs over time.
    case badRequest(Int)

    /// Any other non-2xx status we don't have specific copy for.
    case httpError(Int)

    /// 429 after automatic retries were exhausted. `retryAfter` carries
    /// the `Retry-After` header verbatim so callers can surface a hint.
    case rateLimited(retryAfter: String?)

    /// 2xx, but the payload didn't match the OpenAI-compatible schema.
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "NVIDIA API key is not configured. Add it to Config.xcconfig and rebuild."
        case .unauthorized:
            return "NVIDIA rejected the API key. Check it in Config.xcconfig."
        case .networkError:
            return "Couldn't reach NVIDIA. Check your internet connection."
        case .badRequest(let code):
            return "NVIDIA rejected that request (\(code)). The configured model may be unavailable."
        case .httpError(let code):
            return "NVIDIA server error (\(code)). Try again in a moment."
        case .rateLimited(let retryAfter):
            // A positive Retry-After (seconds form) is the most useful
            // hint we can give; the HTTP-date form falls through to the
            // generic message rather than printing a raw date string.
            if let retryAfter,
               let seconds = Int(retryAfter.trimmingCharacters(in: .whitespaces)),
               seconds > 0 {
                return "NVIDIA rate limit reached. Try again in about \(seconds) seconds."
            }
            return "NVIDIA rate limit reached. Wait a moment and try again."
        case .invalidResponse:
            return "NVIDIA returned an unexpected response."
        }
    }
}

// MARK: - Key loading

/// Thrown when an Info.plist key is absent, empty, or still placeholder.
///
/// Carries only the KEY NAME — never the value — so it is safe to
/// surface, which is exactly what `errorDescription` does.
enum APIKeyError: LocalizedError {
    case missing(infoPlistKey: String)

    var errorDescription: String? {
        switch self {
        case .missing(let infoPlistKey):
            return "\(infoPlistKey) is missing or is still set to the placeholder value."
        }
    }
}

/// Single source of truth for every provider API key in the app.
///
/// One loader, shared by the NVIDIA NIM clients AND the multi-provider
/// `AIChatRouter`, so "never hardcoded, never logged, never in an
/// error" is implemented once rather than per provider. A second copy
/// of this logic is exactly how one provider ends up logging a key.
///
/// Deliberately throws its own neutral error type so this file does not
/// depend on any provider's error taxonomy; each provider maps the
/// failure into whatever its callers already expect.
enum APIKey {

    /// Reads a key from the generated Info.plist.
    ///
    /// - Parameters:
    ///   - infoPlistKey: the Info.plist key name, injected at build time
    ///     from the gitignored Config.xcconfig via
    ///     `INFOPLIST_KEY_<name> = $(<name>)`.
    ///   - placeholderPrefixes: prefixes used by the placeholder text in
    ///     the setup docs, so a forgotten placeholder fails loudly with
    ///     actionable copy instead of producing a 401 half an hour into
    ///     a debugging session.
    static func load(infoPlistKey: String, placeholderPrefixes: [String]) throws -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            throw APIKeyError.missing(infoPlistKey: infoPlistKey)
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !placeholderPrefixes.contains(where: { key.hasPrefix($0) }) else {
            throw APIKeyError.missing(infoPlistKey: infoPlistKey)
        }
        return key
    }

    /// True when a usable key is present. Lets a caller check
    /// configuration without a network call and without catching — this
    /// is what lets the router SKIP a provider that has no key instead
    /// of burning a round-trip on a guaranteed 401.
    static func isConfigured(infoPlistKey: String, placeholderPrefixes: [String]) -> Bool {
        (try? load(infoPlistKey: infoPlistKey, placeholderPrefixes: placeholderPrefixes)) != nil
    }
}

/// NVIDIA NIM key access, kept as the named entry point its callers
/// already use.
///
/// `internal` (not `private`) on purpose: both NIM clients in this
/// layer must load the key through this one function so the placeholder
/// guard and the never-log rule can't be reimplemented subtly wrong.
enum NVIDIAAPIKey {

    /// The Info.plist key injected from Config.xcconfig.
    static let infoPlistKey = "NVIDIA_API_KEY"

    /// Prefix of the placeholder shipped in the setup docs
    /// (`nvapi-YOUR_NEW_KEY_HERE`).
    static let placeholderPrefixes = ["nvapi-YOUR"]

    /// Returns the configured key, or throws `.missingAPIKey`.
    ///
    /// Deliberately never logs and never returns the value in an error.
    static func load() throws -> String {
        do {
            return try APIKey.load(
                infoPlistKey: infoPlistKey,
                placeholderPrefixes: placeholderPrefixes
            )
        } catch is APIKeyError {
            // Preserve this type's long-standing contract: callers of
            // NVIDIAAPIKey already expect NVIDIAError.
            throw NVIDIAError.missingAPIKey
        }
    }

    /// True when a usable key is present. For debug surfaces and
    /// SettingsView so the UI can say "NVIDIA not configured" without
    /// triggering a network call or catching an error.
    static var isConfigured: Bool {
        (try? load()) != nil
    }
}

// MARK: - Transport

/// Shared URLSession transport for the NIM endpoints.
///
/// Responsibilities kept here (so the two clients stay thin):
///   • hard request timeout
///   • `URLError.cancelled` → `CancellationError` passthrough, so a
///     SwiftUI `.task` cancellation isn't misreported as "no internet"
///   • status mapping → `NVIDIAError`
///   • bounded automatic retry on 429 and 5xx, honouring `Retry-After`
///
/// Retry trade-off: every NIM call here is a POST, so a retry after a
/// 5xx *could* mean a second billed generation if the server processed
/// the first request and then failed. Retries are bounded (2) and a 5xx
/// usually means the request was never processed, so the trade-off
/// favours not showing the student a hard error. Pass `retries: 0` at a
/// call site where a duplicate generation is worse than a failure.
enum NIMHTTP {

    /// Automatic retries after the first attempt. Kept small: this is a
    /// foreground tutoring flow, not a background sync.
    static let maxRetries = 2

    /// Ceiling on any single backoff sleep. Without this a server
    /// telling us `Retry-After: 120` would appear to hang the UI.
    static let maxRetryDelay: TimeInterval = 8

    /// Default per-request timeout.
    static let defaultTimeout: TimeInterval = 60

    /// Perform `request` and return the body, or throw `NVIDIAError`.
    ///
    /// - Parameter retries: how many *extra* attempts to allow.
    static func send(_ request: URLRequest, retries: Int = NIMHTTP.maxRetries) async throws -> Data {
        var attempt = 0

        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                // Cancellation is not a network failure. Rethrowing a
                // real CancellationError lets structured concurrency
                // (and `.task` modifiers) unwind correctly.
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    throw CancellationError()
                }
                throw NVIDIAError.networkError
            }

            guard let http = response as? HTTPURLResponse else {
                throw NVIDIAError.invalidResponse
            }

            switch http.statusCode {
            case 200...299:
                return data

            case 401, 403:
                // Never retried: a rejected key will keep being rejected.
                throw NVIDIAError.unauthorized

            case 429:
                let hint = http.value(forHTTPHeaderField: "Retry-After")
                guard attempt < retries else {
                    throw NVIDIAError.rateLimited(retryAfter: hint)
                }
                attempt += 1
                try await sleep(seconds: retryDelay(from: hint) ?? backoff(for: attempt))

            case 400, 404, 422:
                // Not retried: a malformed request or an unknown model
                // fails identically on every attempt.
                throw NVIDIAError.badRequest(http.statusCode)

            case 500...599:
                guard attempt < retries else {
                    throw NVIDIAError.httpError(http.statusCode)
                }
                attempt += 1
                try await sleep(seconds: backoff(for: attempt))

            default:
                throw NVIDIAError.httpError(http.statusCode)
            }
        }
    }

    // MARK: Private

    /// Parses the `Retry-After` header. Only the delta-seconds form is
    /// honoured; the HTTP-date form returns nil and the caller falls
    /// back to exponential backoff. Clamped to `maxRetryDelay`.
    private static func retryDelay(from hint: String?) -> TimeInterval? {
        guard let hint,
              let seconds = TimeInterval(hint.trimmingCharacters(in: .whitespaces)),
              seconds >= 0 else { return nil }
        return min(seconds, maxRetryDelay)
    }

    /// 2s, 4s, 8s… clamped to `maxRetryDelay`.
    private static func backoff(for attempt: Int) -> TimeInterval {
        min(pow(2, Double(attempt)), maxRetryDelay)
    }

    private static func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
    }
}
