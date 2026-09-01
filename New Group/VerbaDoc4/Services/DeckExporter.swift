import Foundation

// MARK: - DeckExporter
//
// Encodes and decodes flashcard sets for cross-device sharing.
// Format: Plain JSON — any text editor can open it.
// File extension: .verbadeck
//
// Export: creates a temp file → iOS share sheet → iMessage / AirDrop / email
// Import: fileImporter reads the JSON → new Document + StudyItems created

// MARK: - Payload

struct ExportedDeck: Codable {
    let version: Int          // bump when format changes
    let title: String
    let cards: [ExportedCard]

    struct ExportedCard: Codable {
        let question: String
        let answer: String
        let topic: String
    }
}

// MARK: - Exporter

enum DeckExporter {

    static let fileExtension = "verbadeck"

    // MARK: - Export

    /// Encodes a Document as a .verbadeck temp file and returns its URL.
    /// Call inside a Task — file I/O is synchronous but lightweight.
    static func exportFile(for document: Document) throws -> URL {
        let deck = ExportedDeck(
            version: 1,
            title: document.title,
            cards: document.studyItems.map {
                ExportedDeck.ExportedCard(
                    question: $0.question,
                    answer: $0.answer,
                    topic: $0.topic
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(deck)

        // Safe filename — strips path-separator characters
        let safe = document.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (safe.isEmpty ? "deck" : safe) + ".\(fileExtension)"
        let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    /// Decodes a .verbadeck (or .json) file. Throws on malformed data.
    static func importFile(from url: URL) throws -> ExportedDeck {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExportedDeck.self, from: data)
    }
}
