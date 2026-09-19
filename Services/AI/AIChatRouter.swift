import Foundation

// MARK: - AIChatRouter
//
// Multi-provider chat router with automatic failover. Tries the
// preferred provider, and on a recoverable failure silently retries the
// SAME prompt on the next one. The student never sees a provider name
// and never sees a rate-limit error.
//
// Why this exists rather than "just pick one provider": both free tiers
// rate-limit, so a single provider is a demo-day single point of
// failure. Failover turns "rate limit hit" into a non-event.
//
// ─────────────────────────────────────────────────────────────────────
// Four things this does that a naive try/catch-around-429 does not:
//
//  1. Fails over on ANY recoverable failure, not just a 429. A 5xx, a
//     timeout, a network blip, an invalid payload, or a bad key on the
//     preferred provider all fail over. Catching only `.rateLimited`
//     means one provider hiccup still shows the student an error.
//
//  2. Fails over FAST. Each provider gets a short timeout and ZERO
//     same-provider retries — the other provider IS the retry. Retrying
//     a rate-limited provider twice before switching turns a 2-second
//     problem into a 20-second stall.
//
//  3. Remembers a failure. Once a provider rate-limits, 5xx's, or
//     rejects the request, it is deprioritised for a cooldown window so
//     the next call goes straight to the healthy one instead of eating
//     the same failure again. A
//     degraded provider is never DROPPED, only reordered — if the
//     healthy one also fails, a degraded provider still beats an error.
//
//  4. Never fails over a cancellation. A cancelled task means the
//     caller went away (view dismissed). That is not a provider fault,
//     so it propagates untouched and costs the provider no cooldown.
// ─────────────────────────────────────────────────────────────────────
//
// Keys: read through `APIKey` from the generated Info.plist, injected
// from the gitignored Config.xcconfig. Never hardcoded, never logged,
// never included in an error.
//
// NAMING: the provider enum is `AIChatProvider`, not `AIProvider`, so it
// cannot collide with the standalone sketch file that declares a
// top-level `AIProvider` — adding both to the target would otherwise be
// an invalid redeclaration.

// MARK: - Provider

enum AIChatProvider: String, Sendable {
    case groq
    case nvidia

    /// Used in the one setup-facing error message. Runtime failure copy
    /// stays provider-neutral on purpose — the student should never learn
    /// which vendor answered.
    var displayName: String {
        switch self {
        case .groq:   return "Groq"
        case .nvidia: return "NVIDIA"
        }
    }
}

/// Everything the router needs to talk to one provider.
struct AIProviderConfig: Sendable {
    let provider: AIChatProvider
    let endpoint: URL
    let model: String
    let infoPlistKey: String
    let placeholderPrefixes: [String]

    /// Per-request ceiling. Short on purpose: a hung provider should cost
    /// one brief pause before failover, not a minute of spinner. Raise
    /// these if you ever request very long generations.
    let timeout: TimeInterval

    /// How long this provider is deprioritised after a recoverable
    /// failure. A rate limit that carries `Retry-After` overrides this
    /// with the server's own hint.
    let cooldown: TimeInterval
}

extension AIProviderConfig {

    /// Priority order: Groq first (fastest for short JSON), NVIDIA NIM
    /// as the fallback.
    ///
    /// MODEL IDs are catalog values and both catalogs change over time —
    /// if a request starts failing with a bad-request error, list what
    /// your key can actually reach (NVIDIA:
    /// `NVIDIAAIService.shared.availableModels()`) before a demo.
    static let defaults: [AIProviderConfig] = [
        AIProviderConfig(
            provider: .groq,
            endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            model: "llama-3.3-70b-versatile",
            infoPlistKey: "GROQ_API_KEY",
            placeholderPrefixes: ["gsk_YOUR"],
            timeout: 20,
            cooldown: 60
        ),
        AIProviderConfig(
            provider: .nvidia,
            endpoint: URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!,
            model: "meta/llama-3.1-70b-instruct",
            infoPlistKey: NVIDIAAPIKey.infoPlistKey,
            placeholderPrefixes: NVIDIAAPIKey.placeholderPrefixes,
            timeout: 25,
            cooldown: 60
        )
    ]
}

// MARK: - Errors

/// Provider-neutral error taxonomy.
///
/// Every `errorDescription` is user-safe and free of keys, hosts, and
/// vendor names — except `.missingKey`, which is a setup-time message a
/// shipping user should never see and which is far more useful with the
/// provider named.
enum AIChatError: LocalizedError {

    /// No provider has a usable key. Checked up front, so this is a
    /// configuration error, not a runtime one.
    case noProviderConfigured

    case missingKey(provider: AIChatProvider)
    case unauthorized
    /// 429. `retryAfter` carries the server's own hint when it sent one,
    /// so the cooldown can honour it instead of always being the fixed
    /// `AIProviderConfig.cooldown`.
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case badRequest(Int)
    case networkError
    case invalidResponse
    case emptyResponse

    /// Every configured provider was tried and failed.
    ///
    /// Carries a redacted per-provider reason: provider names and our own
    /// neutral codes only — never a key, a header value, or a vendor
    /// payload. Nothing renders this to the student (see
    /// `errorDescription`), it exists so a developer can tell WHY both
    /// providers failed without a debugger.
    case allProvidersFailed(reasons: [AIChatProvider: String])

    /// Translates the transport's error type into this neutral one.
    ///
    /// `NIMHTTP` predates the second provider and still reports
    /// `NVIDIAError`; this mapping is what keeps provider-branded errors
    /// from escaping the router, including when the call was to Groq.
    init(transportError error: NVIDIAError, provider: AIChatProvider) {
        switch error {
        case .missingAPIKey:         self = .missingKey(provider: provider)
        case .unauthorized:          self = .unauthorized
        case .networkError:          self = .networkError
        case .rateLimited(let hint): self = .rateLimited(retryAfter: Self.retryAfterSeconds(from: hint))
        case .badRequest(let code):  self = .badRequest(code)
        case .httpError(let code):   self = .serverError(code)
        case .invalidResponse:       self = .invalidResponse
        }
    }

    /// Parses the delta-seconds form of `Retry-After`.
    ///
    /// The HTTP-date form returns nil so the caller falls back to the
    /// provider's default cooldown rather than benching it on a guess.
    ///
    /// Deliberately NOT `NIMHTTP.retryDelay(from:)` even though the parse
    /// is identical: that one clamps to `NIMHTTP.maxRetryDelay` (8s)
    /// because it feeds a sleep. A cooldown must not be truncated to 8
    /// seconds, and a sleep must not be allowed to run for a minute, so
    /// the two callers want genuinely different bounds — clamping happens
    /// at each call site instead (`maxCooldown` here).
    private static func retryAfterSeconds(from hint: String?) -> TimeInterval? {
        guard let hint,
              let seconds = TimeInterval(hint.trimmingCharacters(in: .whitespaces)),
              seconds >= 0 else { return nil }
        return seconds
    }

    /// Short, key-free label used in the router's diagnostic line.
    /// Never shown to the student.
    var diagnosticCode: String {
        switch self {
        case .noProviderConfigured: return "no-key"
        case .missingKey:           return "missing-key"
        case .unauthorized:         return "unauthorized"
        case .rateLimited:          return "rate-limited"
        case .serverError(let code): return "server-\(code)"
        case .badRequest(let code):  return "bad-request-\(code)"
        case .networkError:         return "network"
        case .invalidResponse:      return "invalid-response"
        case .emptyResponse:        return "empty-response"
        case .allProvidersFailed:   return "all-failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No AI provider is configured. Add an API key to Config.xcconfig and rebuild."
        case .missingKey(let provider):
            return "\(provider.displayName)'s API key isn't configured. Add it to Config.xcconfig."
        case .unauthorized:
            return "The AI service rejected the API key. Check Config.xcconfig."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter, seconds > 0 {
                return "The AI service is rate limited. Try again in about \(Int(seconds.rounded())) seconds."
            }
            return "The AI service is rate limited. Try again in a moment."
        case .serverError:
            return "The AI service had a server error. Try again in a moment."
        case .badRequest:
            return "The AI service couldn't handle that request. The configured model may be unavailable."
        case .networkError:
            return "Couldn't reach the AI service. Check your internet connection."
        case .invalidResponse:
            return "The AI returned an unexpected response."
        case .emptyResponse:
            return "The AI returned an empty response. Try again."
        case .allProvidersFailed:
            // Reached only when both providers failed back-to-back. The
            // reasons stay out of user copy on purpose.
            return "Verba's thinking hard — the AI is busy right now. Try again in a sec."
        }
    }
}

// MARK: - Router

/// Serialises provider selection and cooldown state.
///
/// An `actor` because `degradedUntil` is mutable state shared across
/// concurrent generation calls (a quiz fires three requests in a row);
/// a `struct` with a dictionary would be a data race.
actor AIChatRouter {

    static let shared = AIChatRouter()

    private let configs: [AIProviderConfig]

    /// provider → the instant it stops being deprioritised.
    private var degradedUntil: [AIChatProvider: Date] = [:]

    /// Ceiling on a cooldown derived from a server's `Retry-After`.
    ///
    /// A wrong or hostile hint (`Retry-After: 86400`) would otherwise
    /// bench a provider for a day. Over-long cooldowns only cost ordering,
    /// never uptime — a degraded provider is reordered, not dropped — but
    /// a sanity cap keeps the behaviour predictable.
    private static let maxCooldown: TimeInterval = 300

    init(configs: [AIProviderConfig] = AIProviderConfig.defaults) {
        self.configs = configs
    }

    // MARK: Public API

    /// Sends the prompt, failing over between providers.
    ///
    /// - Returns: the reply text plus which provider actually served it.
    ///   The provider is for diagnostics only — never show it in the UI,
    ///   so a fallback is invisible to the student.
    func send(
        system: String,
        userPrompt: String
    ) async throws -> (text: String, provider: AIChatProvider) {
        let candidates = orderedCandidates(now: Date())
        guard !candidates.isEmpty else { throw AIChatError.noProviderConfigured }

        var reasons: [AIChatProvider: String] = [:]

        for config in candidates {
            let attemptStartedAt = Date()
            do {
                let text = try await call(config, system: system, userPrompt: userPrompt)
                // Recovered: stop deprioritising it — but only clear a
                // cooldown this attempt predates. Actor reentrancy means a
                // concurrent `send` can mark the provider degraded during
                // our suspension, and blindly clearing that would send the
                // next caller straight back to a provider we just learned
                // is unhealthy.
                if let until = degradedUntil[config.provider], until <= attemptStartedAt {
                    degradedUntil[config.provider] = nil
                }
                #if DEBUG
                // Failover is invisible to the student by design — which
                // also makes it invisible to YOU while preparing a demo.
                // Log the provider that actually served the request so the
                // fallback is observable in the console. Provider NAME
                // only: never a key, a URL, or a payload.
                let failedOver = config.provider != candidates.first?.provider
                print("[AIChatRouter] served by \(config.provider.rawValue)\(failedOver ? " (failover)" : "")")
                #endif
                return (text, config.provider)
            } catch is CancellationError {
                // The CALLER went away. Not a provider failure: don't fail
                // over, don't cool the provider down.
                throw CancellationError()
            } catch {
                // Anything that isn't already one of ours (a
                // JSONSerialization failure, say) is treated as transient
                // rather than fatal, so the next provider still gets a turn.
                let aiError = (error as? AIChatError) ?? .networkError
                reasons[config.provider] = aiError.diagnosticCode
                #if DEBUG
                // The interesting event while preparing a demo is WHY a
                // provider lost, not just which one eventually won. Reuses
                // the same key-free `diagnosticCode` as the total-failure
                // line, so 429 / 401 / timeout / schema are distinguishable.
                print("[AIChatRouter] \(config.provider.rawValue) failed (\(aiError.diagnosticCode))")
                #endif
                recordFailure(aiError, for: config, now: Date())
            }
        }

        #if DEBUG
        // Key-free by construction: provider names and our own error codes
        // only — never a key, a header, or a vendor payload. Sorted so the
        // line is stable across runs.
        //
        // The string is built INSIDE the `#if` on purpose: hoisting it
        // above would leave an unused binding (a compiler warning) in
        // Release builds, where only `reasons` is consumed by the throw.
        let summary = reasons
            .map { "\($0.key.rawValue): \($0.value)" }
            .sorted()
            .joined(separator: ", ")
        print("[AIChatRouter] all providers failed — \(summary)")
        #endif

        throw AIChatError.allProvidersFailed(reasons: reasons)
    }

    // MARK: Candidate ordering

    /// Configured providers, healthiest first.
    private func orderedCandidates(now: Date) -> [AIProviderConfig] {
        // Only providers that actually have a key. A one-key setup must
        // work without ever attempting the missing provider — attempting
        // it would waste a round-trip and then fail over anyway.
        //
        // Consequence worth knowing: with only one key configured there is
        // no failover at all, only a faster failure.
        let configured = configs.filter { config in
            APIKey.isConfigured(
                infoPlistKey: config.infoPlistKey,
                placeholderPrefixes: config.placeholderPrefixes
            )
        }
        let ready = configured.filter { !isDegraded($0.provider, now: now) }
        let degraded = configured.filter { isDegraded($0.provider, now: now) }

        // Degraded providers are reordered to the back but never dropped:
        // if the healthy one also fails, a rate-limited provider is still
        // better than showing the student an error.
        return ready + degraded
    }

    private func isDegraded(_ provider: AIChatProvider, now: Date) -> Bool {
        guard let until = degradedUntil[provider] else { return false }
        return until > now
    }

    private func recordFailure(_ error: AIChatError, for config: AIProviderConfig, now: Date) {
        switch error {
        case .rateLimited(let retryAfter):
            // Honour the server's own hint when it gave one: benching a
            // provider for 60s because it asked for 5 is pure latency.
            let wait = min(retryAfter ?? config.cooldown, Self.maxCooldown)
            degradedUntil[config.provider] = now.addingTimeInterval(wait)
        case .serverError, .badRequest:
            // Transient. Deprioritise, then try again after the cooldown.
            //
            // `.badRequest` belongs here even though it sounds permanent:
            // in practice it means the configured MODEL is unavailable,
            // which fails identically for a while. Without a cooldown a
            // retired model ID makes every single request pay this
            // provider's full timeout before reaching the healthy one.
            degradedUntil[config.provider] = now.addingTimeInterval(config.cooldown)
        case .noProviderConfigured, .missingKey, .unauthorized,
             .networkError, .invalidResponse, .emptyResponse, .allProvidersFailed:
            // Not worth a cooldown: a bad key or a malformed request fails
            // identically in 60 seconds, and a network blip is usually
            // gone by the next call. Cooling down here would only delay
            // recovery.
            break
        }
    }

    // MARK: Single call

    private func call(
        _ config: AIProviderConfig,
        system: String,
        userPrompt: String
    ) async throws -> String {
        let key = try loadKey(for: config)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = config.timeout

        // Both providers expose the OpenAI-compatible chat schema, so one
        // body shape serves both.
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            // retries: 0 — the fallback provider IS the retry. Retrying the
            // same provider first would turn a 3-second rate limit into a
            // 20-second stall, which is the exact demo risk this service
            // exists to remove.
            data = try await NIMHTTP.send(request, retries: 0)
        } catch is CancellationError {
            throw CancellationError()
        } catch let nvidiaError as NVIDIAError {
            throw AIChatError(transportError: nvidiaError, provider: config.provider)
        } catch {
            throw AIChatError.networkError
        }

        // Two distinct failures, deliberately not collapsed: a decode
        // failure is a schema mismatch on OUR side (or a provider API
        // change), while a missing or blank `content` is the model
        // legitimately returning nothing. Reporting both as "empty
        // response" hides the first one and makes the second look like a bug.
        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            throw AIChatError.invalidResponse
        }
        let text = (decoded.choices.first?.message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIChatError.emptyResponse }
        return text
    }

    private func loadKey(for config: AIProviderConfig) throws -> String {
        do {
            return try APIKey.load(
                infoPlistKey: config.infoPlistKey,
                placeholderPrefixes: config.placeholderPrefixes
            )
        } catch {
            throw AIChatError.missingKey(provider: config.provider)
        }
    }

    // MARK: Wire type

    /// OpenAI-compatible chat completion envelope, shared by both
    /// providers. `content` is optional because a truncated or
    /// content-filtered reply can omit it.
    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }
}

// MARK: - Generation integration
//
// Conforming the router to `StudyGenChatClient` is what gives the
// flashcard / multiple-choice / free-response / quiz generation the same
// failover. `StudyGenService` already defaults to this router, so no
// call site needs changing:
//
//     let gen = StudyGenService()          // failover on
//     let gen = StudyGenService(client: NVIDIAAIService.shared)  // pinned

extension AIChatRouter: StudyGenChatClient {

    /// Fallback system prompt for direct tutor calls. Generation passes
    /// its own (`StudyGenPrompts.system`); the tutor path usually carries
    /// its full instructions in the grounded user prompt already.
    static let defaultSystemPrompt =
        "You are Verba, a friendly and encouraging AI study tutor built into VerbaDoc."

    func completeText(prompt: String, systemPrompt: String?) async throws -> String {
        let result = try await send(
            system: systemPrompt ?? Self.defaultSystemPrompt,
            userPrompt: prompt
        )
        return result.text
    }
}
