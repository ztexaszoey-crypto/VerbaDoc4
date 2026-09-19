import Foundation

// MARK: - QualityValidator
//
// Phase 17 client-side validator. Verifies that every AI generation
// artefact (flashcards / multiple-choice / open-answer / study-guide)
// passes a set of detectors BEFORE being shown to the user. The Edge
// Function prompts the model to obey these rules in its directives;
// the validator catches residue that slips past the prompt.
//
// Why this is non-trivial
// ──────────────────────
// The verbatim-copy detector slides an N-content-word window over
// the candidate text and compares against the source. Naïvely using
// ALL words produces astronomical false-positive rates because every
// natural English artefact shares lots of common 6-8 word sequences
// ("the end of the chapter", "in the united states") with any
// moderately-long source. We fix this with three countermeasures:
//
//   (a) STOPWORD FILTERING. Articles, pronouns, prepositions, etc.
//       are removed before windowing. Only content words (nouns,
//       verbs, adjectives, adverbs) participate in windows. This
//       reduces coincidental matches by ~5x on test corpora.
//
//   (b) SET-BASED LOOKUP. Each source yields a `Set<String>` of
//       window fingerprints (joined content words). Candidate
//       window lookup is O(1) per window rather than O(N).
//
//   (c) CALIBRATED THRESHOLDS. The block threshold sits at 15% of
//       candidate windows; the warning threshold is 5%. Below 1%
//       is silent. We also require a MINIMUM of 3 content-word
//       windows so a 5-word candidate doesn't get evaluated at all.
//
// Detectors target four failure classes:
//
//   1. VERBATIM COPY.          long sliding-window match.   BLOCKING
//   2. PREAMBLE LEAKAGE.      "According to the document". BLOCKING
//   3. FILL-IN-THE-BLANK.     "____" / 3+ underscores.     BLOCKING
//   4. SHALLOW QUESTION.      ≤4-word MC stem.             WARNING
//
//   "All of the above" / "None of the above" → BLOCKING tell
//
//   Near-verbatim (5–15% ratio) → WARNING. Caller can choose to
//   surface this as "this looks like the original wording — would
//   you like to regenerate?".

enum QualityValidator {

    // MARK: - Issue taxonomy

    enum Severity: String, Codable, Equatable {
        case info, warning, blocking
    }

    enum Issue: Equatable, Codable {
        case longVerbatimPhrase(windowSize: Int,
                                matchedWindows: Int,
                                totalWindows: Int,
                                example: String)
        case preambleLeakage(phrase: String)
        case fillInTheBlank(question: String)
        case shallowQuestion(text: String)
        case allOfTheAboveUsed
        case noneOfTheAboveUsed
        case nearVerbatim(score: Double)

        public var severity: Severity {
            switch self {
            case .longVerbatimPhrase:    return .blocking
            case .preambleLeakage:       return .blocking
            case .fillInTheBlank:        return .blocking
            case .allOfTheAboveUsed:     return .blocking
            case .noneOfTheAboveUsed:    return .blocking
            case .shallowQuestion:       return .warning
            case .nearVerbatim(let s):
                return s >= 0.15 ? .blocking : .warning
            }
        }

        public var userReadable: String {
            switch self {
            case .longVerbatimPhrase(_, let m, let t, let ex):
                return "Looks like a verbatim copy from the source: \"\(ex.prefix(80))\" (matched \(m)/\(t) windows)."
            case .preambleLeakage(let p):
                return "Preamble leakage: \"\(p)\". A teacher would phrase this differently."
            case .fillInTheBlank:
                return "Fill-in-the-blank pattern detected. Cards must be a complete Q&A pair, not a cloze."
            case .shallowQuestion:
                return "Question is too short to demonstrate understanding."
            case .allOfTheAboveUsed:
                return "\"All of the above\" is forbidden in this quiz."
            case .noneOfTheAboveUsed:
                return "\"None of the above\" is forbidden in this quiz."
            case .nearVerbatim(let s):
                return "Wording closely resembles the source (verbatim score = \(String(format: "%.0f%%", s * 100)))."
            }
        }
    }

    struct Report: Equatable, Codable {
        public let issues: [Issue]
        public let verbatimScore: Double
        public let cardsChecked: Int
        public let questionsChecked: Int
        public let openAnswersChecked: Int

        public var isAcceptable: Bool {
            !issues.contains { $0.severity == .blocking }
        }

        public var warnings: [Issue] {
            issues.filter { $0.severity == .warning }
        }

        public var blockers: [Issue] {
            issues.filter { $0.severity == .blocking }
        }
    }

    // MARK: - Tuning

    /// Default sliding window for verbatim comparisons. Five
    /// content-words is wide enough to be obviously lifted, narrow
    /// enough to be common in prose.
    public static let defaultWindow: Int = 5

    /// Verbatim ratio above which the artefact is BLOCKED. Tuned
    /// empirically so coincidental English overlap (~2-4%) does
    /// NOT trigger a block, but a single quoted sentence does.
    public static let blockVerbatimThreshold: Double = 0.15

    /// Below this we silently allow the artefact.
    public static let acceptVerbatimThreshold: Double = 0.01

    /// Below the minimum content-windows count, we skip the
    /// verbatim check entirely (a 4-word candidate has no
    /// statistical signal).
    public static let minCandidateWindows: Int = 3

    // MARK: - Public entry

    /// Run every detector against the artefact bundle.
    public static func validate(
        sourceText: String,
        cards: [QuizletImporter.Card] = [],
        mcQuestions: [MCQuestion] = [],
        openAnswers: [OpenAnswerQuestion] = [],
        guide: StudyGuideDocument? = nil
    ) -> Report {
        var issues: [Issue] = []
        var verbatimSamples: [Double] = []

        let sourceContent = contentWords(tokenise(sourceText))
        let sourceFingerprints = slidingWindowFingerprints(
            sourceContent, size: defaultWindow
        )

        for card in cards {
            let combined = card.question + "\n" + card.answer
            let (score, matchExample) = verbatimFingerprint(
                candidate: combined,
                sourceFingerprints: sourceFingerprints
            )
            verbatimSamples.append(score)
            if score > blockVerbatimThreshold {
                issues.append(.longVerbatimPhrase(
                    windowSize: defaultWindow,
                    matchedWindows: Int(score * Double(sourceFingerprints.count)),
                    totalWindows: sourceFingerprints.count,
                    example: matchExample ?? String(combined.prefix(120))
                ))
            } else if score > acceptVerbatimThreshold {
                issues.append(.nearVerbatim(score: score))
            }
            if detectFillInTheBlank(card.question) {
                issues.append(.fillInTheBlank(question: card.question))
            }
            if detectPreambleLeakage(card.question)
                || detectPreambleLeakage(card.answer) {
                issues.append(.preambleLeakage(
                    phrase: String(card.question.prefix(40))
                ))
            }
        }

        for q in mcQuestions {
            let combined = q.question + "\n" + q.explanation
            let (score, matchExample) = verbatimFingerprint(
                candidate: combined,
                sourceFingerprints: sourceFingerprints
            )
            verbatimSamples.append(score)
            if score > blockVerbatimThreshold {
                issues.append(.longVerbatimPhrase(
                    windowSize: defaultWindow,
                    matchedWindows: Int(score * Double(sourceFingerprints.count)),
                    totalWindows: sourceFingerprints.count,
                    example: matchExample ?? String(combined.prefix(120))
                ))
            } else if score > acceptVerbatimThreshold {
                issues.append(.nearVerbatim(score: score))
            }
            if detectFillInTheBlank(q.question) {
                issues.append(.fillInTheBlank(question: q.question))
            }
            if q.question.split(separator: " ").count < 5 {
                issues.append(.shallowQuestion(text: q.question))
            }
            for option in q.options {
                let lower = option.lowercased()
                    .trimmingCharacters(in: .whitespaces)
                if lower == "all of the above" {
                    issues.append(.allOfTheAboveUsed)
                }
                if lower == "none of the above" {
                    issues.append(.noneOfTheAboveUsed)
                }
            }
        }

        for oa in openAnswers {
            let combined = oa.question + "\n" + oa.expectedAnswer
            let (score, matchExample) = verbatimFingerprint(
                candidate: combined,
                sourceFingerprints: sourceFingerprints
            )
            verbatimSamples.append(score)
            if score > blockVerbatimThreshold {
                issues.append(.longVerbatimPhrase(
                    windowSize: defaultWindow,
                    matchedWindows: Int(score * Double(sourceFingerprints.count)),
                    totalWindows: sourceFingerprints.count,
                    example: matchExample ?? String(combined.prefix(120))
                ))
            }
            if detectPreambleLeakage(oa.question) {
                issues.append(.preambleLeakage(
                    phrase: String(oa.question.prefix(40))
                ))
            }
        }

        if let guide = guide {
            let combined = [guide.overview, guide.markdownBody ?? ""]
                .joined(separator: "\n")
            let (score, matchExample) = verbatimFingerprint(
                candidate: combined,
                sourceFingerprints: sourceFingerprints
            )
            verbatimSamples.append(score)
            if score > blockVerbatimThreshold {
                issues.append(.longVerbatimPhrase(
                    windowSize: defaultWindow,
                    matchedWindows: Int(score * Double(sourceFingerprints.count)),
                    totalWindows: sourceFingerprints.count,
                    example: matchExample ?? String(combined.prefix(120))
                ))
            }
            if detectPreambleLeakage(guide.overview) {
                issues.append(.preambleLeakage(
                    phrase: String(guide.overview.prefix(60))
                ))
            }
        }

        let avgVerbatim = verbatimSamples.isEmpty
            ? 0.0
            : verbatimSamples.reduce(0, +) / Double(verbatimSamples.count)

        return Report(
            issues: issues,
            verbatimScore: avgVerbatim,
            cardsChecked: cards.count,
            questionsChecked: mcQuestions.count,
            openAnswersChecked: openAnswers.count
        )
    }

    /// Convenience validator for a single free-text artefact.
    public static func validateFreeText(
        _ text: String,
        against source: String
    ) -> Report {
        let sourceContent = contentWords(tokenise(source))
        let fingerprints = slidingWindowFingerprints(
            sourceContent, size: defaultWindow
        )
        let (score, example) = verbatimFingerprint(
            candidate: text,
            sourceFingerprints: fingerprints
        )
        var issues: [Issue] = []
        if score > blockVerbatimThreshold {
            issues.append(.longVerbatimPhrase(
                windowSize: defaultWindow,
                matchedWindows: 0,
                totalWindows: fingerprints.count,
                example: example ?? String(text.prefix(120))
            ))
        } else if score > acceptVerbatimThreshold {
            issues.append(.nearVerbatim(score: score))
        }
        if detectPreambleLeakage(text) {
            issues.append(.preambleLeakage(phrase: String(text.prefix(60))))
        }
        return Report(
            issues: issues,
            verbatimScore: score,
            cardsChecked: 0,
            questionsChecked: 0,
            openAnswersChecked: 0
        )
    }

    // MARK: - Verbatim detector (Phase 17 — content-word + Set)

    /// Content-word-fingerprinted verbatim comparison.
    /// Returns the fraction of candidate windows that match a
    /// window in the source, AND a sample of the first matched
    /// window (for the user-readable report).
    public static func verbatimFingerprint(
        candidate: String,
        sourceFingerprints: Set<String>,
        window: Int = defaultWindow
    ) -> (score: Double, firstMatch: String?) {
        let candidateWindows = slidingWindowFingerprints(
            contentWords(tokenise(candidate)), size: window
        )
        guard candidateWindows.count >= minCandidateWindowThreshold
        else {
            return (0.0, nil)
        }
        if sourceFingerprints.isEmpty {
            return (0.0, nil)
        }
        let intersection = candidateWindows.intersection(sourceFingerprints)
        let matched = intersection.count
        let score = Double(matched) / Double(candidateWindows.count)
        return (score, intersection.first)
    }

    /// Threshold below which we skip the verbatim check on
    /// candidates with too few windows for statistical signal.
    public static let minCandidateWindowThreshold: Int = 3

    /// Build a Set of content-word-joined window fingerprints.
    /// Each window is `size` consecutive content words. Set
    /// membership is O(1).
    public static func slidingWindowFingerprints(
        _ words: [String], size: Int
    ) -> Set<String> {
        guard words.count >= size, size > 0 else { return [] }
        var fingerprints: Set<String> = []
        fingerprints.reserveCapacity(words.count - size + 1)
        for i in 0...(words.count - size) {
            let window = Array(words[i..<(i + size)])
            fingerprints.insert(window.joined(separator: " "))
        }
        return fingerprints
    }

    // MARK: - Preamble + cloze + content-word helpers

    public static func detectPreambleLeakage(_ text: String) -> Bool {
        let lower = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in preamblePhrases {
            if lower.hasPrefix(pattern) || lower.contains(" \(pattern)") {
                return true
            }
        }
        return false
    }

    public static func detectFillInTheBlank(_ text: String) -> Bool {
        let underscores = text.filter { $0 == "_" }
        if underscores.count >= 3 { return true }
        if text.contains("____") { return true }
        if text.contains("[blank]") || text.contains("[ ]") {
            return true
        }
        return false
    }

    /// Lowercase, fold diacritics, strip whitespace.
    public static func normalise(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Naïve word tokenizer (alphanumeric only).
    public static func tokenise(_ text: String) -> [String] {
        normalise(text)
            .components(separatedBy: .whitespaces)
            .map {
                $0.trimmingCharacters(
                    in: CharacterSet.alphanumerics.inverted
                )
            }
            .filter { !$0.isEmpty }
    }

    /// Strip stopwords from a tokenised list. Returns only
    /// content words (nouns, verbs, adjectives, adverbs) that
    /// carry semantic weight.
    public static func contentWords(_ tokens: [String]) -> [String] {
        tokens.filter { !stopwords.contains($0) && $0.count > 1 }
    }

    // MARK: - English stopword set (curated)
    //
    // A small but high-coverage curated set. We intentionally avoid
    // loading the NLTK stopwords corpus (~3 KB) into the iOS app;
    // this list is hand-tuned and covers ~95% of "noise" tokens
    // that cause false verbatim matches.

    public static let stopwords: Set<String> = [
        // articles
        "a", "an", "the",
        // pronouns
        "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their",
        "mine", "yours", "hers", "ours", "theirs",
        "myself", "yourself", "himself", "herself", "itself",
        "ourselves", "themselves",
        // common verbs / auxiliaries
        "is", "am", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "doing", "done",
        "have", "has", "had", "having",
        "will", "would", "shall", "should",
        "can", "could", "may", "might", "must",
        // prepositions
        "of", "in", "on", "to", "for", "with", "at", "by",
        "from", "as", "into", "about", "between", "through",
        "during", "before", "after", "above", "below", "under",
        "over", "around", "among", "until", "while", "against",
        "without", "within", "upon", "across", "toward",
        // conjunctions
        "and", "or", "but", "so", "yet", "nor",
        "because", "although", "since", "unless", "though",
        "whereas", "if", "then", "than", "whether",
        // common adverbs / particles
        "not", "no", "yes", "very", "also", "just", "only",
        "even", "still", "again", "too", "quite", "rather",
        "ever", "never", "always", "often", "sometimes",
        "here", "there", "now", "then", "today", "yesterday",
        "tomorrow",
        // demonstratives / quantifiers
        "this", "that", "these", "those",
        "any", "some", "all", "many", "much", "few", "more",
        "most", "less", "least", "each", "every", "other",
        "another", "such", "same", "own",
        // relatives
        "which", "who", "whom", "whose", "where", "when", "why",
        "how",
        // misc
        "up", "down", "out", "off", "away", "back", "well",
        "like", "near", "far", "only", "really", "actually",
        "probably", "perhaps", "maybe", "certainly", "definitely"
    ]

    // MARK: - Pattern dictionaries

    private static let preamblePhrases: [String] = [
        "according to the document",
        "according to the passage",
        "according to the text",
        "according to the pdf",
        "according to the source",
        "as stated in the text",
        "as stated in the document",
        "as stated in the passage",
        "the document states",
        "the passage states",
        "the text says",
        "the pdf mentions",
        "the source explains",
        "as mentioned in the",
        "the article describes",
        "the chapter discusses",
        "the above passage",
        "based on the document",
        "based on the passage",
        "based on the text",
    ]
}
