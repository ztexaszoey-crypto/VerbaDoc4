import Foundation
import SwiftData

// MARK: - DeckExporter
//
// Export decks as self-contained JSON so users can share them.
// Import by pasting JSON or opening a .verbadeck file.
//
// Format (stable v1):
// {
//   "version": 1,
//   "title": "...",
//   "cards": [{"question":"...","answer":"...","topic":"..."}]
// }
//
// No server needed — users share via Messages, AirDrop, or any share sheet.

enum DeckExporter {

    // MARK: - Export

    struct ExportedDeck: Codable {
        let version: Int
        let title: String
        let exportedAt: Date
        let cards: [ExportedCard]

        struct ExportedCard: Codable {
            let question: String
            let answer: String
            let topic: String
        }
    }

    /// Encode a Document and its StudyItems to JSON Data.
    static func export(_ document: Document) throws -> Data {
        let cards = document.studyItems.map {
            ExportedDeck.ExportedCard(
                question: $0.question,
                answer: $0.answer,
                topic: $0.topic
            )
        }
        let deck = ExportedDeck(
            version: 1,
            title: document.title,
            exportedAt: Date(),
            cards: cards
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(deck)
    }

    /// Encode a Document to a shareable URL (writes to temp directory).
    static func exportToFile(_ document: Document) throws -> URL {
        let data = try export(document)
        let safeName = document.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .prefix(40)
        let filename = "\(safeName).verbadeck"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case invalidJSON
        case unsupportedVersion(Int)
        case emptyDeck

        var errorDescription: String? {
            switch self {
            case .invalidJSON:              return "Couldn't read the deck file. Make sure you pasted the full export."
            case .unsupportedVersion(let v): return "Deck format v\(v) isn't supported. Update VerbaDoc."
            case .emptyDeck:                return "The deck has no cards."
            }
        }
    }

    /// Parse raw JSON text (pasted by user) into a list of QuizletImporter.Card.
    static func importFromJSON(_ text: String) throws -> (title: String, cards: [QuizletImporter.Card]) {
        guard let data = text.data(using: .utf8) else { throw ImportError.invalidJSON }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let deck: ExportedDeck
        do {
            deck = try decoder.decode(ExportedDeck.self, from: data)
        } catch {
            throw ImportError.invalidJSON
        }

        guard deck.version <= 1 else { throw ImportError.unsupportedVersion(deck.version) }
        guard !deck.cards.isEmpty else { throw ImportError.emptyDeck }

        let cards = deck.cards.map { c in
            var card = QuizletImporter.Card(question: c.question, answer: c.answer)
            card.topic = c.topic
            return card
        }
        return (deck.title, cards)
    }

    /// Try to import from a .verbadeck file URL.
    static func importFromFile(_ url: URL) throws -> (title: String, cards: [QuizletImporter.Card]) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidJSON }
        return try importFromJSON(text)
    }

    // MARK: - Plain text export (for sharing as readable text)

    /// Export as human-readable text (tab-separated, Quizlet-compatible format).
    static func exportAsText(_ document: Document) -> String {
        let header = "# \(document.title)\n\n"
        let cards = document.studyItems
            .map { "\($0.question)\t\($0.answer)" }
            .joined(separator: "\n")
        return header + cards
    }
}
