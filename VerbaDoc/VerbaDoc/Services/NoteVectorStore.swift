import Foundation

// MARK: - NoteVectorStore
//
// The retrieval half of VerbaDoc's RAG tutor pipeline:
//
//   upload → extract text → TextChunker → NIMEmbeddingService(.passage)
//          → NoteVectorStore                                     [once]
//
//   question → NIMEmbeddingService(.query) → cosine similarity →
//            top-k chunks → buildGroundedPrompt(.system) →
//            NVIDIAAIService.complete(...)                        [per turn]
//
// The point: the tutor answers from the student's OWN notes instead of
// generic model knowledge, and says which parts came from the notes.
//
// ─────────────────────────────────────────────────────────────────────
// WIRING — the two touchpoints (see the integration notes in-repo):
//
//  1. After text extraction:
//         try await NoteVectorStore.shared.index(documentID: doc.id,
//                                                text: extractedText)
//
//  2. Instead of sending the raw question to the model:
//         let grounded = try await NoteVectorStore.shared
//             .groundedPrompt(for: question, in: document.id)
//         let answer = try await NVIDIAAIService.shared
//             .complete(prompt: grounded)
//
//     The grounded prompt is only a String, so it feeds whichever chat
//     client generates the answer — NVIDIAAIService here, or an
//     existing Groq client. Only the embedding half has to be NVIDIA.
// ─────────────────────────────────────────────────────────────────────
//
// Concurrency: an `actor`, not a class, because indexing and querying
// both mutate/read the chunk array from async contexts. A plain class
// with a mutable array (as in the first draft of this pipeline) is a
// data race the moment a user asks a question while an upload is still
// being indexed.
//
// Persistence: chunks are cached as JSON in Application Support, keyed
// by document id, so embeddings survive relaunch and a re-upload
// re-indexes only that document. This deliberately avoids a SwiftData
// schema migration and any vector-DB dependency at this scale. Every
// disk operation is best-effort: a failure degrades to in-memory and
// never breaks the tutor.

// MARK: - Chunker

/// Splits extracted PDF / OCR text into retrieval-sized chunks.
///
/// Chunking choices matter more than they look: chunks that straddle
/// two unrelated ideas retrieve badly, and chunks longer than the
/// model's context get rejected or truncated. So this splits on the
/// strongest available boundary first (paragraph → sentence → word),
/// and always hard-caps length.
enum TextChunker {

    /// Splits `text` into chunks of at most `targetSize` characters.
    ///
    /// Uncapped by design: only the caller knows how much of a document
    /// is worth indexing, and only the caller can tell the student what
    /// it dropped. NoteVectorStore applies that cap
    /// (`maxChunksPerDocument`) so the truncation can be reported.
    ///
    /// - Parameter targetSize: character budget per chunk (~500 chars is
    ///   roughly a paragraph and comfortably inside embedding context).
    static func chunk(_ text: String, targetSize: Int = 500) -> [String] {
        guard targetSize > 0 else { return [] }
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }

        /// Packs a piece that is already known to fit `targetSize`.
        func pack(_ piece: String) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if current.isEmpty {
                current = trimmed
            } else if current.count + trimmed.count + 1 <= targetSize {
                current += " " + trimmed
            } else {
                flush()
                current = trimmed
            }
        }

        // Strongest boundary first: paragraphs. A paragraph that fits is
        // kept whole; a long one is decomposed further.
        for paragraph in normalized.components(separatedBy: "\n\n") {
            let para = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !para.isEmpty else { continue }

            if para.count <= targetSize {
                pack(para)
                continue
            }
            for sentence in splitSentences(para) {
                if sentence.count <= targetSize {
                    pack(sentence)
                } else {
                    // A single "sentence" longer than the budget usually
                    // means unpunctuated OCR text or a long list.
                    for piece in splitByWords(sentence, limit: targetSize) {
                        pack(piece)
                    }
                }
            }
        }
        flush()

        return chunks
    }

    // MARK: Private

    /// Normalises line endings, collapses paragraph runs, and squeezes
    /// the horizontal-whitespace runs that OCR loves to emit.
    private static func normalize(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sentence split on terminal punctuation. Intentionally naive about
    /// abbreviations ("e.g.") — over-splitting is harmless here because
    /// neighbouring sentences get repacked into the same chunk.
    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" || character == "\n" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    /// Word-boundary split. Any single "word" past the limit (a URL, a
    /// base64 blob) is hard-split so a chunk can never exceed the cap.
    private static func splitByWords(_ text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let w = String(word)
            if current.isEmpty {
                current = w
            } else if current.count + w.count + 1 <= limit {
                current += " " + w
            } else {
                pieces.append(current)
                current = w
            }
        }
        if !current.isEmpty { pieces.append(current) }

        return pieces.flatMap { piece -> [String] in
            guard piece.count > limit else { return [piece] }
            return stride(from: 0, to: piece.count, by: limit).map { offset in
                let start = piece.index(piece.startIndex, offsetBy: offset)
                let end = piece.index(start, offsetBy: limit, limitedBy: piece.endIndex) ?? piece.endIndex
                return String(piece[start..<end])
            }
        }
    }
}

// MARK: - Chunk

/// One indexed piece of a document plus its embedding vector.
///
/// `Codable` for the on-disk cache. A struct of value types, so it is
/// `Sendable` and can cross the actor boundary safely.
struct NoteChunk: Identifiable, Codable, Equatable, Sendable {

    let id: UUID
    /// Source document (Document.id) — lets us re-index or drop one doc.
    let documentID: String
    let text: String
    let embedding: [Double]

    init(id: UUID = UUID(), documentID: String, text: String, embedding: [Double]) {
        self.id = id
        self.documentID = documentID
        self.text = text
        self.embedding = embedding
    }
}

// MARK: - Index result

/// Outcome of indexing one document.
///
/// Carries the truncation count so the caller can tell the student that
/// only part of a very long document is searchable, rather than letting
/// the tail go missing silently.
struct NoteIndexResult: Sendable, Equatable {

    /// Chunks embedded and stored.
    let indexedChunkCount: Int

    /// Chunks the safety cap discarded. Non-zero means the end of the
    /// document is not retrievable.
    let discardedChunkCount: Int

    var wasTruncated: Bool { discardedChunkCount > 0 }
}

// MARK: - Similarity

/// Pure vector math, kept outside the actor so it is trivially testable
/// and callable without `await`.
enum NoteSimilarity {

    /// Cosine similarity in [-1, 1]. Returns 0 for a dimension mismatch
    /// — which happens if the embedding model is swapped between
    /// indexing and querying — so the query degrades to "no strong
    /// match" instead of crashing or ranking noise.
    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA.squareRoot() * magB.squareRoot())
    }
}

// MARK: - Store

/// Actor-backed, disk-cached vector store for the student's notes.
actor NoteVectorStore {

    static let shared = NoteVectorStore()

    /// Ceiling on chunks indexed per document. Bounds the number of
    /// embedding calls — and therefore upload time and rate-limit
    /// exposure — for a pathological input. Truncation is reported via
    /// `NoteIndexResult.discardedChunkCount`.
    static let maxChunksPerDocument = 500

    private let embedder: NIMEmbeddingService
    private let storageDirectory: URL?

    private var chunks: [NoteChunk] = []
    private var didLoadFromDisk = false

    init(
        embedder: NIMEmbeddingService = .shared,
        storageDirectory: URL? = NoteVectorStore.defaultStorageDirectory()
    ) {
        self.embedder = embedder
        self.storageDirectory = storageDirectory
    }

    /// Application Support — survives relaunch and isn't user-visible.
    ///
    /// Note: Application Support *is* included in iCloud backups on iOS
    /// by default, and embedding vectors are bulky. The index directory
    /// is therefore flagged `isExcludedFromBackup` when it's written
    /// (see `indexesDirectoryForWriting()`): the vectors are fully
    /// re-derivable from the source document, so there's no reason to
    /// spend the user's backup quota on them. Nil disables persistence.
    nonisolated static func defaultStorageDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    // MARK: - Inspection
    //
    // These read like plain properties but are actor-isolated, so call
    // sites need `await` (`await store.indexedChunkCount`). The first
    // read also triggers the lazy disk hydration below.

    /// Number of indexed chunks across all documents.
    var indexedChunkCount: Int {
        loadFromDiskIfNeeded()
        return chunks.count
    }

    var indexedDocumentIDs: Set<String> {
        loadFromDiskIfNeeded()
        return Set(chunks.map(\.documentID))
    }

    func chunkCount(for documentID: String) -> Int {
        loadFromDiskIfNeeded()
        return chunks.filter { $0.documentID == documentID }.count
    }

    /// Every indexed chunk for one document, in indexed order.
    ///
    /// This is the input for GENERATION ("make 10 flashcards from this
    /// document"), which is a different job from retrieval. Retrieval is
    /// query-driven and returns only the k best-matching passages;
    /// generating from a top-3 query result would cover one idea and
    /// call it a study set. Generators want coverage, so they get the
    /// whole document and apply a character budget instead
    /// (`StudyGenContext.sample`).
    func textChunks(for documentID: String) -> [String] {
        loadFromDiskIfNeeded()
        return chunks.filter { $0.documentID == documentID }.map(\.text)
    }

    // MARK: - Indexing

    /// Chunks, embeds, and stores `text` for one document.
    ///
    /// Re-indexing the same document replaces its chunks, so a corrected
    /// upload doesn't leave stale passages retrievable.
    ///
    /// The existing index for the document is only swapped out after
    /// every embedding succeeds, so a failure part-way (offline, 429)
    /// leaves the previous index intact rather than erasing it.
    ///
    /// - Parameter progress: optional `(completed, total)` chunk counts,
    ///   for an upload progress indicator. Called on the actor; hop to
    ///   the main actor inside the closure if you touch UI.
    /// - Returns: a `NoteIndexResult` carrying the indexed and discarded
    ///   chunk counts — check `wasTruncated` before claiming a whole
    ///   document is searchable.
    @discardableResult
    func index(
        documentID: String,
        text: String,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> NoteIndexResult {
        loadFromDiskIfNeeded()

        let allPieces = TextChunker.chunk(text)
        guard !allPieces.isEmpty else { throw NoteIndexError.emptyText }
        let pieces = allPieces.count > Self.maxChunksPerDocument
            ? Array(allPieces.prefix(Self.maxChunksPerDocument))
            : allPieces

        progress?(0, pieces.count)

        var fresh: [NoteChunk] = []
        fresh.reserveCapacity(pieces.count)

        var start = 0
        while start < pieces.count {
            let end = min(start + embedder.batchSize, pieces.count)
            let batch = Array(pieces[start..<end])
            let vectors = try await embedder.embed(batch, inputType: .passage)

            // zip, not index arithmetic: embed() guarantees a 1:1 result
            // ordered to match the batch.
            // `chunkText`, not `text`: `text` is the method's parameter
            // and shadowing it here reads like a bug.
            for (chunkText, vector) in zip(batch, vectors) {
                fresh.append(NoteChunk(documentID: documentID, text: chunkText, embedding: vector))
            }
            start = end
            progress?(start, pieces.count)
        }

        // Atomic swap — only now is the old index discarded.
        chunks.removeAll { $0.documentID == documentID }
        chunks.append(contentsOf: fresh)

        persist(documentID: documentID, chunks: fresh)

        return NoteIndexResult(
            indexedChunkCount: fresh.count,
            discardedChunkCount: allPieces.count - pieces.count
        )
    }

    // MARK: - Retrieval

    /// The `k` chunks most similar to `question`, best first.
    ///
    /// - Parameter documentID: restrict the search to one document.
    ///   Pass this whenever the tutor is opened from a document context.
    ///   Without it, a question about document A can be answered with
    ///   passages from document B — which is exactly the "generic answer"
    ///   failure this pipeline exists to prevent. `nil` searches
    ///   everything indexed, which is right for a global tutor surface.
    func topMatches(
        for question: String,
        k: Int = 3,
        in documentID: String? = nil
    ) async throws -> [NoteChunk] {
        loadFromDiskIfNeeded()

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NoteIndexError.emptyText }

        let searchable = documentID.map { id in chunks.filter { $0.documentID == id } } ?? chunks
        guard !searchable.isEmpty else {
            // Distinguish "nothing indexed at all" from "this document
            // isn't ready yet" — the student-facing fix differs.
            throw documentID == nil
                ? NoteIndexError.noDocumentsIndexed
                : NoteIndexError.documentNotIndexed
        }

        let query = try await embedder.embed(trimmed, inputType: .query)

        // A model swap between indexing and querying (or a cache written
        // by an older model) yields vectors of a different width, which
        // makes EVERY cosine score 0. Retrieval would then quietly
        // return nothing and the tutor would silently turn into a
        // generic chatbot — the exact failure this pipeline exists to
        // prevent — with no signal anywhere. Fail loudly instead.
        // `contains`, not just a check on the first chunk: a stale cache
        // alongside a freshly re-indexed document leaves a MIXED-width
        // store, and the mismatched half would still score 0 and be
        // dropped silently by the filter below.
        if searchable.contains(where: { $0.embedding.count != query.count }) {
            throw NoteIndexError.embeddingModelChanged
        }

        // Note: `\KeyPath` cannot address tuple elements, so these two
        // steps use closures rather than key paths.
        return searchable
            .map { (chunk: $0, score: NoteSimilarity.cosine($0.embedding, query)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(k)
            .map { $0.chunk }
    }

    /// Convenience: retrieve, then build the grounded prompt in one call.
    /// This is what the tutor call site should use.
    func groundedPrompt(
        for question: String,
        k: Int = 3,
        in documentID: String? = nil
    ) async throws -> String {
        let matches = try await topMatches(for: question, k: k, in: documentID)
        return Self.buildGroundedPrompt(question: question, context: matches.map(\.text))
    }

    // MARK: - Prompt building

    /// Builds the retrieval-augmented tutor prompt.
    ///
    /// `nonisolated static` and free of I/O so the exact wording can be
    /// unit-tested against a fixed context array.
    nonisolated static func buildGroundedPrompt(question: String, context: [String]) -> String {
        let contextBlock = context
            .enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let sourceBlock = contextBlock.isEmpty
            ? "No matching notes found — answer from general knowledge and say so plainly."
            : contextBlock

        return """
        You are Verba, a friendly and encouraging AI study tutor built into VerbaDoc. \
        A student is asking you a question. Below is relevant material pulled directly \
        from their own notes — use it as your primary source of truth. If the notes don't \
        fully answer the question, say so plainly, then fill the gap with your own knowledge \
        and make clear which parts came from their notes versus general knowledge.

        Explain like you're a patient tutor who wants the student to actually understand, \
        not just get an answer to copy. Keep it concise: 2-4 short paragraphs max, or a short \
        list if that's clearer. Never sound like a generic chatbot disclaimer machine — be warm \
        and specific to what they're studying.

        STUDENT'S NOTES (most relevant excerpts):
        \(sourceBlock)

        STUDENT'S QUESTION:
        \(question)
        """
    }

    // MARK: - Maintenance

    /// Drops one document's index (called when a document is deleted).
    func removeIndex(for documentID: String) {
        loadFromDiskIfNeeded()
        chunks.removeAll { $0.documentID == documentID }
        try? FileManager.default.removeItem(at: storageURL(for: documentID))
    }

    /// Drops every index (called on sign-out / delete-account).
    func clearAll() {
        chunks.removeAll()
        didLoadFromDisk = true
        guard let dir = indexesDirectory() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Persistence (best-effort)

    /// Read path — no side effects, so a fresh install doesn't create
    /// directories merely because something asked whether an index
    /// exists.
    private func indexesDirectory() -> URL? {
        guard let storageDirectory else { return nil }
        return storageDirectory.appendingPathComponent("note-vectors", isDirectory: true)
    }

    /// Write path — creates the directory on demand and keeps it out of
    /// iCloud backups.
    private func indexesDirectoryForWriting() -> URL? {
        guard let dir = indexesDirectory() else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var mutableDir = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutableDir.setResourceValues(values)
        } catch {
            // Best-effort: the in-memory index still works without a
            // cache, it just costs a re-index next launch.
        }
        return dir
    }

    private func storageURL(for documentID: String) -> URL? {
        guard let dir = indexesDirectory() else { return nil }
        return dir.appendingPathComponent(Self.fileName(for: documentID))
    }

    /// Canonical cache filename for a document. One function so read,
    /// write, delete, and load-time validation can't disagree.
    private static func fileName(for documentID: String) -> String {
        "\(sanitize(documentID)).json"
    }

    /// Document ids may be UUIDs today but could become paths; strip
    /// anything that isn't filesystem-safe so a future id can't escape
    /// the cache directory.
    private static func sanitize(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleaned = raw.map { allowed.contains($0) ? $0 : "_" }
        // Two different ids can collapse to the same safe string (every
        // unsafe character becomes "_"), which would let one document's
        // index overwrite another's. The fingerprint of the RAW id keeps
        // the filename injective.
        //
        // Deliberately not `hashValue`: Swift seeds that per process, so
        // the filename would change every launch and no cached index
        // would ever be found again.
        // Hoisted rather than nested inside the interpolation: nested
        // string literals inside \( ) are easy to corrupt on edit.
        let base = cleaned.isEmpty ? "unknown" : String(cleaned)
        return "\(base)-\(fingerprint(raw))"
    }

    /// FNV-1a (32-bit): deterministic across launches and runs, which
    /// `hashValue` is not.
    private static func fingerprint(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash, radix: 16)
    }

    private func persist(documentID: String, chunks: [NoteChunk]) {
        guard indexesDirectoryForWriting() != nil,
              let url = storageURL(for: documentID) else { return }
        do {
            let data = try JSONEncoder().encode(chunks)
            try data.write(to: url, options: .atomic)
        } catch {
            // In-memory index is still valid; losing the cache only costs
            // a re-index next launch.
        }
    }

    /// Lazily hydrates the in-memory index on first use, so launch time
    /// isn't spent deserialising vectors nobody has asked for yet.
    private func loadFromDiskIfNeeded() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let dir = indexesDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
              ) else { return }

        // Keyed by document so each document contributes its chunks at
        // most once. Blindly concatenating every file would double-count
        // a document whenever a stale file is still on disk (e.g. one
        // written under an older filename scheme).
        var byDocument: [String: [NoteChunk]] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let decoded = try? JSONDecoder().decode([NoteChunk].self, from: data),
                  let documentID = decoded.first?.documentID else { continue }
            // Only the file matching the current naming scheme is
            // authoritative for that document.
            guard file.lastPathComponent == Self.fileName(for: documentID) else { continue }
            byDocument[documentID] = decoded
        }
        chunks = byDocument.values.flatMap { $0 }
    }
}

// MARK: - Free-function shim
//
// Kept so the original pipeline sketch's call site still reads the same
// way. Delegates to the actor method — the prompt text itself lives in
// exactly one place (NoteVectorStore.buildGroundedPrompt).

func buildGroundedTutorPrompt(question: String, store: NoteVectorStore) async throws -> String {
    try await store.groundedPrompt(for: question)
}
