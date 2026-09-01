import Foundation

// MARK: - SecurityValidator
//
// Central gate for all text entering or leaving VerbaDoc.
// Every string that goes to Groq or gets written to SwiftData must pass through here.
//
// What it does
// ────────────
//  • Sanitize  — strips null bytes, control characters, and normalises whitespace.
//  • Validate  — rejects inputs that exceed size limits (prevents prompt-stuffing
//                and sky-high token bills from malformed/adversarial content).
//
// Size limits are conservative; raise them if legitimate content gets rejected.

enum SecurityValidator {

    // MARK: - Limits

    /// Raw document content fed to the AI. Raised to support large PDFs/textbooks.
    /// The generator chunks this into 7 500-char AI calls so the model never sees
    /// more than one chunk per request regardless of document size.
    static let maxContentCharacters   = 200_000

    /// Full prompt string passed to GroqAPI.chat() including system + user parts.
    static let maxPromptCharacters    = 15_000

    /// Per-card field limits stored in SwiftData.
    static let maxQuestionCharacters  =    500
    static let maxAnswerCharacters    =  1_000

    /// Maximum title length for a Document.
    static let maxTitleCharacters     =    200

    // MARK: - Sanitise

    /// Strips null bytes and non-printable control characters (keeps newlines and tabs).
    /// Normalises runs of whitespace and trims leading/trailing space.
    /// Safe to call on any string — never throws.
    static func sanitize(_ input: String) -> String {
        var result = input

        // Remove null bytes
        result = result.replacingOccurrences(of: "\0", with: "")

        // Remove control characters except \n (0x0A), \r (0x0D), \t (0x09)
        result = result.unicodeScalars.filter { scalar in
            let v = scalar.value
            // Allow printable ASCII/Unicode + whitespace we want to keep
            return v >= 0x20 || v == 0x09 || v == 0x0A || v == 0x0D
        }.reduce(into: "") { $0.append(Character($1)) }

        // Collapse runs of blank lines (more than 2 consecutive newlines → 2)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Validate (throws on violation)

    /// Sanitises and checks document content size. Call before building any prompt.
    @discardableResult
    static func validateContent(_ text: String) throws -> String {
        let clean = sanitize(text)
        guard clean.count <= maxContentCharacters else {
            throw ValidationError.tooLarge(
                field: "document content",
                actual: clean.count,
                limit:  maxContentCharacters
            )
        }
        return clean
    }

    /// Sanitises and checks a full prompt string. Call inside GroqAPI.chat().
    @discardableResult
    static func validatePrompt(_ text: String) throws -> String {
        let clean = sanitize(text)
        guard clean.count <= maxPromptCharacters else {
            throw ValidationError.tooLarge(
                field: "prompt",
                actual: clean.count,
                limit:  maxPromptCharacters
            )
        }
        return clean
    }

    /// Sanitises and validates a card question/answer pair.
    /// Returns the cleaned versions or throws if invalid.
    static func validateCard(
        question: String,
        answer:   String
    ) throws -> (question: String, answer: String) {
        let q = sanitize(question)
        let a = sanitize(answer)

        guard !q.isEmpty else { throw ValidationError.emptyField("question") }
        guard !a.isEmpty else { throw ValidationError.emptyField("answer") }

        guard q.count <= maxQuestionCharacters else {
            throw ValidationError.tooLarge(field: "question", actual: q.count, limit: maxQuestionCharacters)
        }
        guard a.count <= maxAnswerCharacters else {
            throw ValidationError.tooLarge(field: "answer", actual: a.count, limit: maxAnswerCharacters)
        }
        return (q, a)
    }

    /// Sanitises and validates a document title.
    @discardableResult
    static func validateTitle(_ text: String) throws -> String {
        let clean = sanitize(text)
        guard !clean.isEmpty else { throw ValidationError.emptyField("title") }
        guard clean.count <= maxTitleCharacters else {
            throw ValidationError.tooLarge(field: "title", actual: clean.count, limit: maxTitleCharacters)
        }
        return clean
    }

    // MARK: - Error

    enum ValidationError: LocalizedError {
        case tooLarge(field: String, actual: Int, limit: Int)
        case emptyField(String)
        case malformed(field: String, detail: String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let field, let actual, let limit):
                return "\(field) is too large (\(actual) characters). Maximum is \(limit)."
            case .emptyField(let field):
                return "\(field) cannot be empty."
            case .malformed(let field, let detail):
                return "\(field) contains invalid data: \(detail)"
            }
        }
    }
}
