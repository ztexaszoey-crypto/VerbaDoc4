import Foundation

// MARK: - StudyGenService
//
// Orchestrates: prompt → chat model → tolerant JSON decode → structural
// validation → typed items. Nothing here talks to a specific vendor.
//
// The transport is a protocol (`StudyGenChatClient`) precisely so
// generation never depends on one vendor. Two conformances exist:
//
//   • `AIChatRouter` (the default below) — tries Groq, fails over to
//     NVIDIA. Every generation call inherits the failover for free.
//   • `NVIDIAAIService` — NVIDIA only, no failover.
//
// The protocol method is deliberately NOT named `complete(prompt:)`:
// that would collide with the client's own method of the same shape and
// make the conformance body call itself. Naming it `completeText`
// removes the ambiguity entirely.

// MARK: - Transport

/// Minimal surface a generation model has to offer.
///
/// `Sendable` so conforming clients can be held by a `Sendable` service
/// and shared across tasks.
protocol StudyGenChatClient: Sendable {
    func completeText(prompt: String, systemPrompt: String?) async throws -> String
}

/// `NVIDIAAIService` already satisfies this shape, so the models just
/// need the exact protocol signature.
extension NVIDIAAIService: StudyGenChatClient {
    func completeText(prompt: String, systemPrompt: String?) async throws -> String {
        try await complete(prompt: prompt, systemPrompt: systemPrompt)
    }
}

// MARK: - Service

struct StudyGenService: Sendable {

    private let client: any StudyGenChatClient

    /// - Parameter client: defaults to the multi-provider router, so every
    ///   generation call inherits automatic Groq → NVIDIA failover. Pass a
    ///   specific client (`NVIDIAAIService.shared`) to pin one provider.
    init(client: any StudyGenChatClient = AIChatRouter.shared) {
        self.client = client
    }

    // MARK: Flashcards

    func flashcards(from noteText: String, count: Int = 10) async throws
        -> StudyGen.Batch<StudyGen.Flashcard> {
        let prompt = StudyGenPrompts.flashcards(noteText: try requireText(noteText), count: count)
        let dtos = try await request(prompt: prompt) {
            try StudyGenJSON.decodeArray(StudyGen.FlashcardDTO.self, from: $0)
        }
        return StudyGenValidation.flashcards(from: dtos)
    }

    // MARK: Multiple choice

    func multipleChoice(from noteText: String, count: Int = 5) async throws
        -> StudyGen.Batch<StudyGen.MultipleChoiceQuestion> {
        let prompt = StudyGenPrompts.multipleChoice(
            noteText: try requireText(noteText),
            count: count
        )
        let dtos = try await request(prompt: prompt) {
            try StudyGenJSON.decodeArray(StudyGen.MultipleChoiceDTO.self, from: $0)
        }
        return StudyGenValidation.multipleChoice(from: dtos)
    }

    // MARK: Free response

    func freeResponse(from noteText: String, count: Int = 3) async throws
        -> StudyGen.Batch<StudyGen.FreeResponseQuestion> {
        let prompt = StudyGenPrompts.freeResponse(
            noteText: try requireText(noteText),
            count: count
        )
        let dtos = try await request(prompt: prompt) {
            try StudyGenJSON.decodeArray(StudyGen.FreeResponseDTO.self, from: $0)
        }
        return StudyGenValidation.freeResponse(from: dtos)
    }

    // MARK: Grading

    /// Grades with partial credit. The score is arithmetic over the
    /// rubric points, not a number the model chose.
    func grade(
        question: String,
        keyPoints: [String],
        studentAnswer: String
    ) async throws -> StudyGen.FreeResponseGrade {
        let prompt = StudyGenPrompts.grade(
            question: question,
            keyPoints: keyPoints,
            studentAnswer: studentAnswer
        )
        let dto = try await request(prompt: prompt) {
            try StudyGenJSON.decodeObject(StudyGen.GradeDTO.self, from: $0)
        }
        return StudyGenValidation.grade(from: dto)
    }

    // MARK: Notes outline

    func outline(from noteText: String) async throws -> StudyGen.NotesOutline {
        let prompt = StudyGenPrompts.outline(noteText: try requireText(noteText))
        let dto = try await request(prompt: prompt) {
            try StudyGenJSON.decodeObject(StudyGen.OutlineDTO.self, from: $0)
        }
        return StudyGenValidation.outline(from: dto)
    }

    // MARK: Quiz assembly

    /// Builds a real mixed session and attaches the source document id.
    ///
    /// Requests run SEQUENTIALLY on purpose: three concurrent calls on a
    /// free/fast tier is a reliable way to collect 429s, and the user is
    /// already looking at a loading state. If you later want the latency
    /// back, this is the one function to make concurrent.
    ///
    /// Throws `.noUsableItems` only when all three modes came back empty,
    /// so one weak section degrades the session instead of failing it.
    func quiz(
        from noteText: String,
        flashcardCount: Int = 4,
        multipleChoiceCount: Int = 4,
        freeResponseCount: Int = 2,
        sourceDocumentID: String? = nil
    ) async throws -> StudyGen.QuizSession {
        let text = try requireText(noteText)

        let cardBatch = try await flashcards(from: text, count: flashcardCount)
        let mcBatch = try await multipleChoice(from: text, count: multipleChoiceCount)
        let frBatch = try await freeResponse(from: text, count: freeResponseCount)

        let session = StudyGen.QuizSession(
            flashcards: cardBatch.items,
            multipleChoice: mcBatch.items,
            freeResponse: frBatch.items,
            sourceDocumentID: sourceDocumentID,
            droppedCount: cardBatch.droppedCount + mcBatch.droppedCount + frBatch.droppedCount
        )
        guard !session.isEmpty else { throw StudyGenError.noUsableItems }
        return session
    }

    /// Convenience for the RAG path: sample across a document's indexed
    /// chunks, then build a quiz from that.
    ///
    /// Generation uses a coverage sample (`StudyGenContext.sample`) rather
    /// than `topMatches` — a quiz built from the three passages most
    /// similar to a single query would cover one idea and call it a
    /// study set.
    func quiz(
        forDocument documentID: String,
        in store: NoteVectorStore,
        flashcardCount: Int = 4,
        multipleChoiceCount: Int = 4,
        freeResponseCount: Int = 2
    ) async throws -> StudyGen.QuizSession {
        let chunks = await store.textChunks(for: documentID)
        let context = StudyGenContext.sample(from: chunks)
        return try await quiz(
            from: context,
            flashcardCount: flashcardCount,
            multipleChoiceCount: multipleChoiceCount,
            freeResponseCount: freeResponseCount,
            sourceDocumentID: documentID
        )
    }

    // MARK: Internals

    /// Sends the prompt and runs the caller's decoder over the reply, so
    /// every mode shares one system prompt and one parsing policy.
    ///
    /// The decoder is a closure rather than a `T.Type` because these
    /// endpoints return BOTH top-level arrays (flashcards, multiple
    /// choice, free response) and top-level objects (outline, grade). A
    /// generic object decoder would extract `{...},{...}` from an array
    /// reply and fail every list mode, so array-vs-object stays an
    /// explicit decision at each call site.
    private func request<T>(
        prompt: String,
        decode: (String) throws -> T
    ) async throws -> T {
        let reply = try await client.completeText(
            prompt: prompt,
            systemPrompt: StudyGenPrompts.system
        )
        // An empty body would otherwise surface as `.invalidJSON`, which
        // misattributes a transport problem to the model's formatting.
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StudyGenError.invalidJSON }
        return try decode(trimmed)
    }

    private func requireText(_ noteText: String) throws -> String {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StudyGenError.emptyNoteText }
        return trimmed
    }
}
