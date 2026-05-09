import Foundation
import Combine

final class StudyGenerator {
    static let shared = StudyGenerator()
    private static let fallbackQuestionWordCount = 8
    private static let fallbackAnswerWordCount = 6

    private init() {}

    static func generateCards(from text: String, documentTitle: String? = nil, maxCards: Int = 20) -> [StudyItem] {
        shared.generateCards(from: text, documentTitle: documentTitle, maxCards: maxCards)
    }

    func generateCards(from text: String, documentTitle: String? = nil, maxCards: Int = 20) -> [StudyItem] {
        guard maxCards > 0 else { return [] }

        let cleanedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedText.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ".!?\n")
        let rawSegments = cleanedText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let uniqueSegments = rawSegments.filter { segment in
            let normalized = segment.lowercased()
            if seen.contains(normalized) { return false }
            seen.insert(normalized)
            return true
        }

        var cards: [StudyItem] = []

        for segment in uniqueSegments {
            if cards.count >= maxCards { break }

            let words = segment.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard words.count >= 4 else { continue }

            guard let focusWord = words
                .map(String.init)
                .filter({ $0.count >= 4 })
                .sorted(by: { $0.count > $1.count })
                .first
            else {
                continue
            }

            let masked = segment.replacingOccurrences(of: focusWord, with: "____", options: [.caseInsensitive, .diacriticInsensitive])
            guard masked != segment else { continue }

            let explanationPrefix = documentTitle?.isEmpty == false ? "From \(documentTitle!):" : "From your material:"
            let explanation = "\(explanationPrefix) \(segment)"

            cards.append(
                StudyItem(
                    question: masked,
                    answer: focusWord,
                    explanation: explanation,
                    documentTitle: documentTitle
                )
            )
        }

        if cards.isEmpty {
            let words = cleanedText.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if words.count >= 6 {
                let question = words.prefix(Self.fallbackQuestionWordCount).joined(separator: " ")
                let answer = words
                    .dropFirst(Self.fallbackQuestionWordCount)
                    .prefix(Self.fallbackAnswerWordCount)
                    .joined(separator: " ")
                cards.append(
                    StudyItem(
                        question: "Continue this thought: \(question)…",
                        answer: answer.isEmpty ? question : answer,
                        explanation: cleanedText,
                        documentTitle: documentTitle
                    )
                )
            }
        }

        return cards
    }
}
