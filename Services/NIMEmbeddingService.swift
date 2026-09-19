import Foundation

// MARK: - NIMEmbeddingService
//
// Retrieval-embeddings client for NVIDIA's hosted NIM API
// (https://integrate.api.nvidia.com/v1/embeddings). OpenAI-compatible
// REST, so this is a plain POST — no SDK.
//
// This is the "understand the student's own notes" half of the RAG
// pipeline: text chunks are embedded once at upload time, the tutor
// question is embedded at ask time, and the two are compared with
// cosine similarity. See NoteVectorStore for the store + retrieval.
//
// KEY SECURITY: the key is loaded through NVIDIAAPIKey (NIMCore), the
// same path NVIDIAAIService uses — i.e. from the gitignored
// Config.xcconfig via the generated Info.plist. It is never hardcoded,
// never logged, and never included in an error.
//
// Declared as a `struct` with only immutable stored properties so it is
// automatically `Sendable` and can be safely held by the
// NoteVectorStore actor without an extra lock.
//
// VERIFICATION: the model ID and the `input_type` / `truncate` fields
// are part of NVIDIA's catalog contract, which changes over time. If a
// request starts failing with a 400/404, call
// `NVIDIAAIService.shared.availableModels()` to see what this key can
// actually reach, then set `model` accordingly.
//
// Batch size note: NVIDIA applies dynamic batching server-side and
// recommends keeping client batches modest (8–32 inputs). 16 is a good
// default: fewer round-trips than one-at-a-time, without risking the
// timeout/429 behaviour that very large batches provoke on the free tier.

struct NIMEmbeddingService: Sendable {

    /// Shared instance on the default embedding model.
    static let shared = NIMEmbeddingService()

    // MARK: - Types

    /// Asymmetric retrieval input type.
    ///
    /// Retrieval models are trained to embed a *query* and a *passage*
    /// into the same space but with different projections. Indexing with
    /// the wrong one degrades recall quietly — which is exactly why this
    /// is an enum and not a `String` at the call site.
    enum InputType: String {
        /// Document / note text being indexed.
        case passage
        /// The student's question being searched with.
        case query
    }

    // MARK: - Configuration

    /// Hosted NIM embedding model. Swappable via `init(model:)`.
    ///
    /// Model IDs on the catalog change over time; if this 404s, list
    /// what your key can reach with
    /// `NVIDIAAIService.shared.availableModels()`.
    let model: String

    /// Maximum inputs per HTTP request. See the batch-size note above.
    let batchSize: Int

    /// Optional server-side overflow handling for over-length input.
    ///
    /// Defaults to `nil`, which omits the field entirely: an unknown
    /// field is a 400 risk on a model that doesn't accept it, and the
    /// chunker already caps chunk length well inside the model's
    /// context. Use `"END"` only if you start feeding it raw OCR dumps.
    let truncate: String?

    private let endpoint = URL(string: "https://integrate.api.nvidia.com/v1/embeddings")!
    private let timeout: TimeInterval

    init(
        model: String = "nvidia/nemotron-3-embed-1b",
        batchSize: Int = 16,
        truncate: String? = nil,
        timeout: TimeInterval = NIMHTTP.defaultTimeout
    ) {
        // Guard against a nonsensical batch size silently looping.
        self.model = model
        self.batchSize = max(1, batchSize)
        self.truncate = truncate
        self.timeout = timeout
    }

    // MARK: - Public API

    /// Embed a single string. Convenience over the batch API.
    func embed(_ text: String, inputType: InputType) async throws -> [Double] {
        guard let vector = try await embed([text], inputType: inputType).first else {
            throw NoteIndexError.emptyText
        }
        return vector
    }

    /// Embed many strings, batching to keep request count sane.
    ///
    /// Results are returned in the SAME ORDER as `texts` (1:1), because
    /// the store pairs each vector back to its chunk by position.
    ///
    /// Throws `.emptyText` if any input is blank rather than silently
    /// dropping it — dropping would misalign vectors and chunks, which
    /// would corrupt retrieval in a way that's very hard to debug.
    func embed(_ texts: [String], inputType: InputType) async throws -> [[Double]] {
        let cleaned = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleaned.isEmpty else { throw NoteIndexError.emptyText }
        guard cleaned.allSatisfy({ !$0.isEmpty }) else { throw NoteIndexError.emptyText }

        var vectors: [[Double]] = []
        vectors.reserveCapacity(cleaned.count)

        var start = 0
        while start < cleaned.count {
            let end = min(start + batchSize, cleaned.count)
            let batch = Array(cleaned[start..<end])
            vectors.append(contentsOf: try await embedBatch(batch, inputType: inputType))
            start = end
        }
        return vectors
    }

    // MARK: - Private

    /// One HTTP request for one batch. Ordering and count are both
    /// validated before returning.
    private func embedBatch(_ batch: [String], inputType: InputType) async throws -> [[Double]] {
        let apiKey = try NVIDIAAPIKey.load()

        var body: [String: Any] = [
            "input": batch,
            "model": model,
            "input_type": inputType.rawValue,
            "encoding_format": "float"
        ]
        if let truncate { body["truncate"] = truncate }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await NIMHTTP.send(request)

        guard let decoded = try? JSONDecoder().decode(EmbeddingResponse.self, from: data) else {
            throw NVIDIAError.invalidResponse
        }

        // The API returns an `index` per item; sort by it instead of
        // trusting array order, then verify we got one vector per input.
        let ordered = decoded.data.sorted { $0.resolvedIndex < $1.resolvedIndex }
        guard ordered.count == batch.count else {
            throw NVIDIAError.invalidResponse
        }
        return ordered.map(\.embedding)
    }

    // MARK: - Wire type

    private struct EmbeddingResponse: Decodable {
        struct Item: Decodable {
            let index: Int?
            let embedding: [Double]

            /// Position of this vector in the request. Falls back to a
            /// stable value if a server omits `index` (it shouldn't).
            var resolvedIndex: Int { index ?? 0 }
        }
        let data: [Item]
    }
}

// MARK: - Errors owned by the retrieval layer
//
// Kept separate from NVIDIAError: these describe *content* problems
// (no notes indexed, nothing to search), not transport failures, and
// their copy is directed at the student rather than at the developer.

enum NoteIndexError: LocalizedError {

    /// Nothing embeddable — an empty upload, or whitespace-only text.
    case emptyText

    /// The student asked a question before any notes were indexed.
    case noDocumentsIndexed

    /// The question was scoped to a document that isn't indexed yet —
    /// opened before its upload finished, or the index was cleared.
    case documentNotIndexed

    /// The stored vectors and the query vector have different widths, so
    /// they were produced by different embedding models. Retrieval is
    /// meaningless until the document is re-indexed.
    case embeddingModelChanged

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "There's no readable text to search in that material."
        case .noDocumentsIndexed:
            return "Upload a document first and I'll answer from your own notes."
        case .documentNotIndexed:
            return "This document hasn't been read yet. Upload it and I'll answer from its contents."
        case .embeddingModelChanged:
            return "These notes were indexed with a different model. Re-upload the document so I can search it again."
        }
    }
}
