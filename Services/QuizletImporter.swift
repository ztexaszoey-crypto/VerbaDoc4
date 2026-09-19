import Foundation

// MARK: - QuizletImporter
//
// Parses text exported from Quizlet into (question, answer) pairs.
//
// Quizlet's "Export" screen lets users choose two separators:
//   - Between term and definition (default: TAB)
//   - Between cards (default: NEWLINE)
//
// Common real-world export formats this handles:
//   1. TAB-separated, newline per card      → "term\tdefinition\nterm\tdefinition"
//   2. Comma-separated, newline per card    → "term,definition"
//   3. Semicolon-separated, newline per card
//   4. Q:/A: explicit labels               → "Q: term\nA: definition"
//   5. Numbered pairs                       → "1. term\n   definition"
//   6. Dash/bullet pairs                   → "- term\n  definition"
//   7. Plain prose / notes                 → sentence-level extraction (fallback)
//
// Detection order: most-specific first, prose last.

enum QuizletImporter {

    struct Card: Identifiable {
        let id = UUID()
        var question: String
        var answer: String
        var topic: String = ""
    }

    // MARK: - Public entry point

    /// Parse raw text (pasted from Quizlet or typed notes) into Cards.
    /// Returns an empty array if nothing useful can be extracted.
    static func parse(_ text: String) -> [Card] {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !cleaned.isEmpty else { return [] }

        // Try formats in specificity order
        if let cards = tryTabSeparated(cleaned),   !cards.isEmpty { return cards }
        if let cards = tryQALabeled(cleaned),       !cards.isEmpty { return cards }
        if let cards = tryNumberedPairs(cleaned),   !cards.isEmpty { return cards }
        if let cards = trySemicolonSeparated(cleaned), !cards.isEmpty { return cards }
        if let cards = tryCommaSeparated(cleaned),  !cards.isEmpty { return cards }
        if let cards = tryAlternateProse(cleaned),  !cards.isEmpty { return cards }
        return []
    }

    // MARK: - Detect format

    static func detectedFormat(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        if cleaned.contains("\t") { return "Quizlet export (tab-separated)" }
        if cleaned.lowercased().contains("\nq:") || cleaned.lowercased().hasPrefix("q:") {
            return "Q/A format"
        }
        let firstLine = cleaned.components(separatedBy: "\n").first ?? ""
        if firstLine.contains(";") { return "Semicolon-separated" }
        if firstLine.contains(",") { return "Comma-separated" }
        if firstLine.first?.isNumber == true { return "Numbered list" }
        return "Plain notes"
    }

    // MARK: - Format parsers

    /// Format 1: term TAB definition NEWLINE ... (Quizlet default export)
    private static func tryTabSeparated(_ text: String) -> [Card]? {
        guard text.contains("\t") else { return nil }
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let cards: [Card] = lines.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            let q = parts[0].trimmingCharacters(in: .whitespaces)
            let a = parts[1...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty, !a.isEmpty else { return nil }
            return Card(question: q, answer: a)
        }
        return cards.isEmpty ? nil : cards
    }

    /// Format 2: Q: ... / A: ... label pairs
    private static func tryQALabeled(_ text: String) -> [Card]? {
        let lower = text.lowercased()
        guard lower.contains("q:") || lower.contains("question:") else { return nil }

        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var cards: [Card] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let lineLower = line.lowercased()
            if lineLower.hasPrefix("q:") || lineLower.hasPrefix("question:") {
                let q = extractAfterColon(line)
                var a = ""
                if i + 1 < lines.count {
                    let next = lines[i + 1]
                    let nextLower = next.lowercased()
                    if nextLower.hasPrefix("a:") || nextLower.hasPrefix("answer:") {
                        a = extractAfterColon(next)
                        i += 2
                    } else {
                        i += 1
                    }
                } else {
                    i += 1
                }
                if !q.isEmpty && !a.isEmpty {
                    cards.append(Card(question: q, answer: a))
                }
            } else {
                i += 1
            }
        }
        return cards.isEmpty ? nil : cards
    }

    /// Format 3: 1. term\n   definition (or term on one line, definition on next)
    private static func tryNumberedPairs(_ text: String) -> [Card]? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first, first.first?.isNumber == true, first.contains(".") else { return nil }

        var cards: [Card] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Match "1. term" pattern
            let stripped = line.replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
            if stripped != line && i + 1 < lines.count {
                let next = lines[i + 1]
                let nextStripped = next.replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                if !stripped.isEmpty && !next.isEmpty {
                    cards.append(Card(question: stripped, answer: nextStripped.isEmpty ? next : nextStripped))
                    i += 2
                    continue
                }
            }
            i += 1
        }
        return cards.count >= 2 ? cards : nil
    }

    /// Format 4: term;definition
    private static func trySemicolonSeparated(_ text: String) -> [Card]? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.first?.contains(";") == true else { return nil }
        let cards: [Card] = lines.compactMap { line in
            let parts = line.components(separatedBy: ";")
            guard parts.count >= 2 else { return nil }
            let q = parts[0].trimmingCharacters(in: .whitespaces)
            let a = parts[1...].joined(separator: ";").trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty, !a.isEmpty else { return nil }
            return Card(question: q, answer: a)
        }
        // Require at least 2 valid pairs and >60% of lines parsed
        let parseRate = Double(cards.count) / Double(lines.count)
        return (cards.count >= 2 && parseRate > 0.6) ? cards : nil
    }

    /// Format 5: term,definition (careful — natural text contains commas)
    private static func tryCommaSeparated(_ text: String) -> [Card]? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // Only try if lines are SHORT (< 80 chars) — long lines are prose, not pairs
        guard lines.allSatisfy({ $0.count < 100 }) else { return nil }
        let cards: [Card] = lines.compactMap { line in
            // Only split on FIRST comma to handle definitions that contain commas
            guard let commaIdx = line.firstIndex(of: ",") else { return nil }
            let q = String(line[line.startIndex..<commaIdx]).trimmingCharacters(in: .whitespaces)
            let a = String(line[line.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty, !a.isEmpty else { return nil }
            return Card(question: q, answer: a)
        }
        let parseRate = Double(cards.count) / Double(lines.count)
        return (cards.count >= 2 && parseRate > 0.7) ? cards : nil
    }

    /// Format 6: prose / notes — extract sentences as definition prompts
    private static func tryAlternateProse(_ text: String) -> [Card]? {
        // Split on sentence boundaries
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 5 }  // min 5 words

        guard sentences.count >= 3 else { return nil }

        // Turn each informational sentence into a cloze-style question
        let cards: [Card] = sentences.prefix(20).compactMap { sentence in
            guard let keyWord = extractKeyTerm(from: sentence) else {
                return Card(question: "Explain: \(sentence.prefix(90))", answer: sentence)
            }
            // Phase 10: removed cloze "_____" fill-in-the-blank behavior.
            // The TeacherBlueprint.swift directive forbids cloze on the
            // AI path; keep the offline fall-back here aligned with the
            // same rule — emit a proper Front/Back Q&A pair instead.
            return Card(
                question: "Explain the significance of: \(keyWord)",
                answer: sentence
            )
        }
        return cards.isEmpty ? nil : cards
    }

    // MARK: - Helpers

    private static func extractAfterColon(_ line: String) -> String {
        guard let colonIdx = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Very basic: find the longest word in the sentence that looks like a key term.
    private static func extractKeyTerm(from sentence: String) -> String? {
        let words = sentence.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 5 && $0.first?.isUppercase == true }
        return words.max(by: { $0.count < $1.count })
    }
}
