import Foundation

// MARK: - StudyGen
//
// The structured-output vocabulary for AI study-material generation.
//
// Namespaced behind `StudyGen.` on purpose: VerbaDoc already has
// flashcard and quiz concepts (StudyItem, the CapySurfers
// StudyChallenge, the card-generation path). These types describe what
// the MODEL returns, which is a different thing from what the app
// stores, so the boundary is explicit and can't collide with an
// existing model name.
//
// ─────────────────────────────────────────────────────────────────────
// The rule this file exists to enforce:
//
//     A prompt can only SUGGEST a shape. Only code can GUARANTEE it.
//
// `answer: String` happily holds a 400-word paragraph, and
// `correctIndex: Int` happily holds 9 against 4 options. Prompts drift,
// especially on a fast/free tier, so every generated item passes
// through `StudyGenValidation` before it can reach a view. Violations
// are DROPPED and COUNTED (`Batch.droppedCount`) — never silently
// rendered as the ChatGPT-wrapper output the whole design is trying to
// avoid.
// ─────────────────────────────────────────────────────────────────────

enum StudyGen {

    // MARK: - Wire types (exactly what the model returns)
    //
    // Decodable-only, one per JSON shape. Kept separate from the domain
    // types below so decoding can't be confused with validation: the DTO
    // is allowed to be malformed, the domain type is not.

    struct FlashcardDTO: Decodable {
        let term: String
        let answer: String
    }

    struct OptionDTO: Decodable {
        let text: String
        let misconception: String?
    }

    struct MultipleChoiceDTO: Decodable {
        let question: String
        let options: [OptionDTO]
        let correctIndex: Int
    }

    struct FreeResponseDTO: Decodable {
        let question: String
        let keyPoints: [String]
    }

    struct GradeDTO: Decodable {
        let pointsHit: [String]
        let pointsMissed: [String]
        let feedback: String
    }

    struct OutlineDTO: Decodable {
        struct SectionDTO: Decodable {
            let heading: String
            let bullets: [String]
        }
        let sections: [SectionDTO]
        let glossary: [FlashcardDTO]
    }

    // MARK: - Domain types (what the app uses)

    /// A term plus a deliberately tiny answer. The answer is capped in
    /// `StudyGenValidation`, not just asked for in the prompt.
    struct Flashcard: Identifiable, Sendable, Equatable {
        let id: UUID
        let term: String
        let answer: String

        init(id: UUID = UUID(), term: String, answer: String) {
            self.id = id
            self.term = term
            self.answer = answer
        }
    }

    /// One multiple-choice option.
    ///
    /// `misconception` is the field that makes this generation layer
    /// feed the Misconception Mapping engine rather than just produce
    /// quiz filler: when the student picks this option, the stored
    /// phrase tells the app *which* misunderstanding they hold, not
    /// merely that they were wrong.
    struct MultipleChoiceOption: Sendable, Equatable {
        let text: String
        let misconception: String?
    }

    struct MultipleChoiceQuestion: Identifiable, Sendable, Equatable {
        let id: UUID
        let question: String
        let options: [MultipleChoiceOption]
        let correctIndex: Int

        init(
            id: UUID = UUID(),
            question: String,
            options: [MultipleChoiceOption],
            correctIndex: Int
        ) {
            self.id = id
            self.question = question
            self.options = options
            self.correctIndex = correctIndex
        }

        /// Safe lookup — never traps if `correctIndex` is somehow out of
        /// range. Validation guarantees it isn't, but a model-facing
        /// value should not be allowed to crash a view.
        var correctOption: MultipleChoiceOption? {
            options.indices.contains(correctIndex) ? options[correctIndex] : nil
        }
    }

    struct FreeResponseQuestion: Identifiable, Sendable, Equatable {
        let id: UUID
        let question: String
        let keyPoints: [String]

        init(id: UUID = UUID(), question: String, keyPoints: [String]) {
            self.id = id
            self.question = question
            self.keyPoints = keyPoints
        }
    }

    /// Rubric-based grading result.
    ///
    /// `score` is computed from the rubric hit/miss lists rather than
    /// read from the model. Asking an LLM for a number invites a number
    /// that doesn't follow from its own rubric — partial credit should
    /// be arithmetic, not opinion.
    struct FreeResponseGrade: Sendable, Equatable {
        let pointsHit: [String]
        let pointsMissed: [String]
        let feedback: String

        /// 0...1.
        var score: Double {
            let total = pointsHit.count + pointsMissed.count
            guard total > 0 else { return 0 }
            return Double(pointsHit.count) / Double(total)
        }

        var scorePercent: Int { Int((score * 100).rounded()) }
    }

    struct NotesOutline: Sendable, Equatable {
        struct Section: Sendable, Equatable {
            let heading: String
            let bullets: [String]
        }
        let sections: [Section]
        let glossary: [Flashcard]

        /// Sections and glossary entries the validator rejected for
        /// violating the shape contract. Reported rather than hidden, so
        /// the notes view can say the outline is partial instead of
        /// quietly showing an incomplete one.
        let droppedItemCount: Int
    }

    /// A scored study session: mixed item types generated from one note
    /// set. Assembled by `StudyGenService.quiz(from:)`.
    ///
    /// `sourceDocumentID` is attached by the app, never requested from
    /// the model — LLMs get IDs wrong, and the SM-2 writeback needs a
    /// correct one.
    struct QuizSession: Sendable {
        var flashcards: [Flashcard]
        var multipleChoice: [MultipleChoiceQuestion]
        var freeResponse: [FreeResponseQuestion]
        var sourceDocumentID: String?
        var droppedCount: Int

        var totalItems: Int {
            flashcards.count + multipleChoice.count + freeResponse.count
        }

        var isEmpty: Bool { totalItems == 0 }
    }

    /// Generated items plus how many were rejected for violating the
    /// contract. Truncation is reported, never hidden.
    struct Batch<Element: Sendable>: Sendable {
        let items: [Element]
        let droppedCount: Int

        var isEmpty: Bool { items.isEmpty }
    }
}

// MARK: - Errors

enum StudyGenError: LocalizedError {

    /// Nothing to generate from.
    case emptyNoteText

    /// The model's reply contained no decodable JSON.
    case invalidJSON

    /// JSON decoded, but every item violated the shape contract.
    case noUsableItems

    var errorDescription: String? {
        switch self {
        case .emptyNoteText:
            return "There's no text in these notes to generate from yet."
        case .invalidJSON:
            return "The AI's reply wasn't in the expected format. Tap to try again."
        case .noUsableItems:
            return "The AI couldn't produce usable study items from this section. Try a different one."
        }
    }
}

// MARK: - Tolerant JSON extraction
//
// The sketch that this pipeline is based on decoded the raw reply
// directly. That fails on the two things models do most often: wrap the
// JSON in ```json fences, or lead with a sentence ("Here are your
// flashcards:"). Both produce a decode failure that looks like a model
// quality problem when it's really a parsing one.

enum StudyGenJSON {

    /// Decode a top-level JSON array, tolerating fences and prose.
    static func decodeArray<T: Decodable>(_ type: T.Type, from raw: String) throws -> [T] {
        for candidate in candidates(in: raw, opening: "[", closing: "]") {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([T].self, from: data) else { continue }
            return decoded
        }
        throw StudyGenError.invalidJSON
    }

    /// Decode a top-level JSON object, tolerating fences and prose.
    static func decodeObject<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        for candidate in candidates(in: raw, opening: "{", closing: "}") {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(T.self, from: data) else { continue }
            return decoded
        }
        throw StudyGenError.invalidJSON
    }

    /// Successive candidate JSON substrings, most promising first.
    ///
    /// Each candidate runs from one opening bracket to the LAST closing
    /// bracket of that kind. Choosing the last closing bracket is what
    /// makes nested structures work (tagged options, outline sections) —
    /// pairing the first `[` with the FIRST `]` truncates at the first
    /// nested object.
    ///
    /// It returns several candidates rather than one because a reply's
    /// prose can contain stray brackets. For "Here are your flashcards
    /// [see below]: [...]" a single first-bracket guess yields a garbage
    /// substring and fails, while the next candidate is the real payload.
    /// Trying a handful is far cheaper than a wasted model round-trip.
    static func candidates(
        in raw: String,
        opening: Character,
        closing: Character,
        limit: Int = 8
    ) -> [String] {
        let cleaned = stripCodeFences(raw)
        guard let lastClosing = cleaned.lastIndex(of: closing) else { return [] }

        var found: [String] = []
        var searchStart = cleaned.startIndex
        while found.count < limit,
              let open = cleaned[searchStart...].firstIndex(of: opening),
              open < lastClosing {
            found.append(String(cleaned[open...lastClosing]))
            searchStart = cleaned.index(after: open)
        }
        return found
    }

    /// Removes a ```json ... ``` wrapper if present. Returns the input
    /// unchanged when there's no fence.
    private static func stripCodeFences(_ raw: String) -> String {
        guard let openingFence = raw.range(of: "```") else { return raw }
        var body = raw[openingFence.upperBound...]

        // Drop a language tag on the fence line ("```json").
        if let newline = body.firstIndex(of: "\n") {
            let firstLine = body[body.startIndex..<newline]
            if !firstLine.contains("{"), !firstLine.contains("[") {
                body = body[body.index(after: newline)...]
            }
        }
        if let closingFence = body.range(of: "```") {
            return String(body[body.startIndex..<closingFence.lowerBound])
        }
        return String(body)
    }
}

// MARK: - Validation
//
// Every check here is something a prompt promised and code now enforces.
// Nothing is repaired in place — a malformed item is dropped, because a
// half-fixed flashcard teaches the wrong thing.

enum StudyGenValidation {

    /// Multiple choice must have exactly this many options.
    static let requiredOptionCount = 4

    /// Word ceiling for a flashcard answer. The prompt asks for 1–4; the
    /// extra word of slack avoids dropping good cards over an article,
    /// while still making a sentence impossible.
    static let maxAnswerWords = 5

    /// Character ceiling as a backstop for a single 200-character "word".
    static let maxAnswerCharacters = 60

    /// Rubric points a free-response question must carry to be gradable.
    static let minKeyPoints = 2
    static let maxKeyPoints = 4

    // MARK: Flashcards

    static func flashcards(from dtos: [StudyGen.FlashcardDTO]) -> StudyGen.Batch<StudyGen.Flashcard> {
        var kept: [StudyGen.Flashcard] = []
        var seen = Set<String>()
        var dropped = 0

        for dto in dtos {
            let term = dto.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = dto.answer.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !term.isEmpty,
                  !answer.isEmpty,
                  wordCount(answer) <= maxAnswerWords,
                  answer.count <= maxAnswerCharacters else {
                dropped += 1
                continue
            }
            // Two identical terms would show the student the same card
            // twice and double-count it in SM-2.
            let key = normalized(term)
            guard seen.insert(key).inserted else {
                dropped += 1
                continue
            }
            kept.append(StudyGen.Flashcard(term: term, answer: answer))
        }
        return StudyGen.Batch(items: kept, droppedCount: dropped)
    }

    // MARK: Multiple choice

    static func multipleChoice(
        from dtos: [StudyGen.MultipleChoiceDTO]
    ) -> StudyGen.Batch<StudyGen.MultipleChoiceQuestion> {
        var kept: [StudyGen.MultipleChoiceQuestion] = []
        var dropped = 0

        for dto in dtos {
            let question = dto.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let options = dto.options.map {
                StudyGen.MultipleChoiceOption(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    misconception: cleanedTag($0.misconception)
                )
            }

            guard !question.isEmpty,
                  options.count == requiredOptionCount,
                  options.allSatisfy({ !$0.text.isEmpty }),
                  options.indices.contains(dto.correctIndex) else {
                dropped += 1
                continue
            }
            // Duplicate options hand the student a free win AND make
            // `correctIndex` ambiguous, so the item is unusable.
            let distinct = Set(options.map { normalized($0.text) })
            guard distinct.count == options.count else {
                dropped += 1
                continue
            }
            kept.append(
                StudyGen.MultipleChoiceQuestion(
                    question: question,
                    options: options,
                    correctIndex: dto.correctIndex
                )
            )
        }
        return StudyGen.Batch(items: kept, droppedCount: dropped)
    }

    // MARK: Free response

    static func freeResponse(
        from dtos: [StudyGen.FreeResponseDTO]
    ) -> StudyGen.Batch<StudyGen.FreeResponseQuestion> {
        var kept: [StudyGen.FreeResponseQuestion] = []
        var dropped = 0

        for dto in dtos {
            let question = dto.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let points = dto.keyPoints
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Without 2+ rubric points there's nothing to award partial
            // credit against, so it degrades into an ungraded prompt.
            guard !question.isEmpty,
                  points.count >= minKeyPoints,
                  points.count <= maxKeyPoints else {
                dropped += 1
                continue
            }
            kept.append(StudyGen.FreeResponseQuestion(question: question, keyPoints: points))
        }
        return StudyGen.Batch(items: kept, droppedCount: dropped)
    }

    // MARK: Grading + outline

    static func grade(from dto: StudyGen.GradeDTO) -> StudyGen.FreeResponseGrade {
        StudyGen.FreeResponseGrade(
            pointsHit: dto.pointsHit.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            pointsMissed: dto.pointsMissed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            feedback: dto.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func outline(from dto: StudyGen.OutlineDTO) -> StudyGen.NotesOutline {
        let sections = dto.sections.compactMap { section -> StudyGen.NotesOutline.Section? in
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            let bullets = section.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !heading.isEmpty, !bullets.isEmpty else { return nil }
            return StudyGen.NotesOutline.Section(heading: heading, bullets: bullets)
        }
        // Glossary entries obey the same short-answer contract as cards.
        let glossaryBatch = flashcards(from: dto.glossary)

        return StudyGen.NotesOutline(
            sections: sections,
            glossary: glossaryBatch.items,
            droppedItemCount: (dto.sections.count - sections.count) + glossaryBatch.droppedCount
        )
    }

    // MARK: Helpers

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Maps a missing or whitespace-only misconception tag to nil, so a
    /// sloppy `" "` from the model can't render as an empty tag.
    ///
    /// Deliberately an explicit `guard` rather than optional chaining
    /// with a helper: `raw?.trimmed.nilIfEmpty` compiles, but it depends
    /// on the optional chain flattening a nested optional, which is too
    /// subtle to leave in a file other people will edit.
    private static func cleanedTag(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
