import Foundation
import SwiftData

class StudyGenerator {
    static let shared = StudyGenerator()
    
    init() {}
    
    // MARK: - Public Methods
    
    func generateFlashcards(for document: Document) async throws {
        let prompt = """
        Generate comprehensive flashcard study materials from the following text.
        Create 5-10 question-answer pairs that cover the key concepts.
        Format as JSON array with objects containing "question" and "answer" fields.
        
        Text:
        \(document.content)
        
        Return ONLY valid JSON, no markdown or explanations.
        """
        
        let explanation = try await GroqAPI.shared.generateFlashcardExplanation(
            question: "Generate flashcards",
            answer: document.content
        )
        
        let flashcards = try parseFlashcards(from: explanation)
        
        // Save to SwiftData
        for flashcard in flashcards {
            let studyItem = StudyItem(
                question: flashcard.question,
                answer: flashcard.answer
            )
            studyItem.document = document
            document.studyItems.append(studyItem)
        }
    }
    
    func regenerateFlashcards(for document: Document) async throws {
        // Clear existing flashcards
        document.studyItems.removeAll()
        
        // Generate new ones
        try await generateFlashcards(for: document)
    }
    
    // MARK: - Private Methods
    
    private func parseFlashcards(from json: String) throws -> [FlashcardData] {
        // Extract JSON from potential markdown code blocks
        var jsonString = json
        if jsonString.contains("```json") {
            if let start = jsonString.range(of: "```json"),
               let end = jsonString.range(of: "```", range: jsonString.index(start.lowerBound, offsetBy: 7)..<jsonString.endIndex) {
                jsonString = String(jsonString[start.upperBound..<end.lowerBound])
            }
        }
        
        let decoder = JSONDecoder()
        let flashcards = try decoder.decode([FlashcardData].self, from: jsonString.data(using: .utf8)!)
        return flashcards
    }
}

// MARK: - Models

struct FlashcardData: Codable {
    let question: String
    let answer: String
}
