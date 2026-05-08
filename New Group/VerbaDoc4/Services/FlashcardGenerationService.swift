import Foundation

enum FlashcardGenerationService {
    static func generateCards(from text: String, documentTitle: String, groqAPIKey: String) async -> [StudyItem] {
        let trimmedKey = groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            do {
                let tasks = try await GroqAPI.generateTasks(from: text, apiKey: trimmedKey, maxTasks: 12)
                let items = GroqAPI.toStudyItems(tasks, documentTitle: documentTitle)
                if !items.isEmpty {
                    return items
                }
            } catch {
                // Fall back to local generation below.
            }
        }

        return StudyGenerator.generateCards(from: text, documentTitle: documentTitle, maxCards: 12)
    }
}
