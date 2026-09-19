import Foundation

// MARK: - NVIDIAAIService
//
// Thin OpenAI-compatible client for NVIDIA's hosted NIM API
// (https://integrate.api.nvidia.com/v1). Dedicated service layer —
// no feature code in VerbaDoc talks to NVIDIA directly.
//
// Sits on NIMCore for key loading, error taxonomy, and transport
// (timeouts, cancellation passthrough, 429/5xx retry).
//
// Key security contract: see NIMCore.swift. The key comes from the
// generated Info.plist (`NVIDIA_API_KEY`, injected from the gitignored
// Config.xcconfig) and is never hardcoded, logged, or put in an error.
//
// The model is configurable rather than hard-coded at call sites:
// either use `NVIDIAAIService.shared` (default model) or construct your
// own instance with a different model for a specific job.
//
// `.shared` remains the intended entry point for feature code. The
// initializer is public only so a caller with a genuinely different job
// (a small classifier model, a different sampling profile) can
// configure one deliberately instead of mutating shared state.

/// `Sendable` because every stored property is an immutable value type
/// (String / Double / TimeInterval / URL), so instances are safe to
/// share across actors and tasks without a lock.
final class NVIDIAAIService: Sendable {

    /// Shared instance on the default model. Inject via `.shared`
    /// (matches CardGenerationService.shared / AuthService.shared).
    static let shared = NVIDIAAIService()

    // MARK: - Configuration

    /// Default hosted NIM chat model.
    ///
    /// `let` on purpose: it is configured once, at construction, so the
    /// service is safe to use from concurrent tasks without a lock.
    /// Need a different model? `NVIDIAAIService(model: "…")`.
    /// To check what your key can actually reach, see
    /// `availableModels()` below — model IDs on the catalog change.
    let model: String

    /// Sampling defaults, kept as properties so a feature can supply its
    /// own turn without editing this file.
    let defaultTemperature: Double
    let defaultTopP: Double

    private let endpoint = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
    private let modelsEndpoint = URL(string: "https://integrate.api.nvidia.com/v1/models")!
    private let timeout: TimeInterval

    /// - Parameters:
    ///   - model: hosted NIM model ID.
    ///   - timeout: per-request timeout; NIM generations can be slow,
    ///     so the default is generous.
    init(
        model: String = "nvidia/nemotron-3-super-120b-a12b",
        temperature: Double = 1,
        topP: Double = 0.95,
        timeout: TimeInterval = NIMHTTP.defaultTimeout
    ) {
        self.model = model
        self.defaultTemperature = temperature
        self.defaultTopP = topP
        self.timeout = timeout
    }

    // MARK: - Public API

    /// Send one simple prompt and return the model's text reply.
    ///
    /// This is the smoke-test entry point: call it from any debug surface
    /// to confirm key + network + model are all wired correctly.
    func completeSimplePrompt(_ prompt: String) async throws -> String {
        try await complete(prompt: prompt)
    }

    /// General-purpose single-turn completion.
    ///
    /// - Parameters:
    ///   - prompt: the user message.
    ///   - systemPrompt: optional system message. Used by the grounded
    ///     tutor path (see NoteVectorStore) to carry the instructions
    ///     that keep answers anchored to the student's own notes.
    ///   - maxTokens: response cap. Defaults to 2048 — enough for a
    ///     2–4 paragraph tutoring answer. Raise it for long-form output.
    ///   - temperature: sampling temperature for this call.
    ///   - topP: nucleus sampling for this call.
    func complete(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 2048,
        temperature: Double? = nil,
        topP: Double? = nil
    ) async throws -> String {
        let apiKey = try NVIDIAAPIKey.load()

        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature ?? defaultTemperature,
            "top_p": topP ?? defaultTopP,
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await NIMHTTP.send(request)

        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
              let raw = decoded.choices.first?.message.content else {
            throw NVIDIAError.invalidResponse
        }
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw NVIDIAError.invalidResponse }
        return content
    }

    /// Lists the model IDs this key can reach.
    ///
    /// Debug helper: NVIDIA's catalog changes over time, so if a request
    /// starts 404-ing, call this and check the ID you're configuring
    /// still exists. Not used by the app's normal flow.
    func availableModels() async throws -> [String] {
        let apiKey = try NVIDIAAPIKey.load()

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        let data = try await NIMHTTP.send(request)

        guard let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
            throw NVIDIAError.invalidResponse
        }
        return decoded.data.map(\.id).sorted()
    }
}

// MARK: - Wire types

extension NVIDIAAIService {

    /// OpenAI-compatible chat completion envelope.
    ///
    /// `reasoning_content` is decoded separately from `content` so a
    /// thinking model's chain-of-thought can never be mistaken for the
    /// answer. Only `content` is returned to callers.
    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            let message: Message
        }
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let choices: [Choice]
    }

    private struct ModelListResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }
}
