import Foundation

// MARK: - StudyTask

struct StudyTask: Codable {
    let question: String
    let answer: String
    let explanation: String
}

// MARK: - GroqAPI

enum GroqAPI {
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    /// llama3-8b-8192: 8B parameter LLaMA 3 model with an 8,192-token context window.
    private static let model = "llama3-8b-8192"
    /// Maximum characters of source text sent to the API to stay within the model's context window.
    private static let maxInputTextLength = 3000

    enum GroqAPIError: Error {
        case invalidResponse
        case emptyContent
        case decodingFailed
    }

    /// Generates study flashcard tasks from text using the Groq AI API.
    /// - Parameters:
    ///   - text: The source text to generate cards from.
    ///   - apiKey: A valid Groq API key.
    ///   - maxTasks: Maximum number of cards to request (default 10).
    /// - Returns: An array of `StudyTask` values decoded from the model's JSON response.
    static func generateTasks(
        from text: String,
        apiKey: String,
        maxTasks: Int = 10
    ) async throws -> [StudyTask] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let truncatedText = String(text.prefix(maxInputTextLength))
        let systemPrompt = """
        You are a helpful study assistant that creates concise flashcard pairs. \
        Return ONLY a valid JSON array where each element has exactly these fields: \
        "question", "answer", and "explanation". Do not include any other text.
        """
        let userPrompt = """
        Generate \(maxTasks) study flashcard pairs from the following text:

        \(truncatedText)
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GroqAPIError.invalidResponse
        }

        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)

        guard let content = groqResponse.choices.first?.message.content,
              !content.isEmpty
        else {
            throw GroqAPIError.emptyContent
        }

        // The model may wrap the JSON in a markdown code block; strip it.
        let jsonString = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GroqAPIError.decodingFailed
        }

        let tasks = try JSONDecoder().decode([StudyTask].self, from: jsonData)
        return tasks
    }

    /// Converts an array of `StudyTask` values to `StudyItem` SwiftData models.
    static func toStudyItems(_ tasks: [StudyTask], documentTitle: String? = nil) -> [StudyItem] {
        tasks.map { task in
            StudyItem(
                question: task.question,
                answer: task.answer,
                explanation: task.explanation,
                documentTitle: documentTitle
            )
        }
    }
}

// MARK: - Groq response types (private)

private struct GroqResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
