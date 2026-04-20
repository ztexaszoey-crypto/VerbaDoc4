import Foundation

struct StudyGenerator {
    func generateItems(from text: String, documentTitle: String? = nil, limit: Int = 10) -> [StudyItem] {
        let cleanedLines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = cleanedLines.isEmpty ? [text.trimmingCharacters(in: .whitespacesAndNewlines)] : cleanedLines
        return source
            .prefix(max(1, limit))
            .enumerated()
            .map { index, line in
                StudyItem(
                    question: "What is key point \(index + 1)?",
                    answer: String(line),
                    explanation: "Review this point from your material.",
                    documentTitle: documentTitle
                )
            }
    }
}
