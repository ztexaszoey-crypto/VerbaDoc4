import Foundation

class GroqAPI {
    static let shared = GroqAPI()
    
    private let apiKey: String
    private let baseURL = "https://api.groq.com/openai/v1"
    
    init() {
        // Load API key from environment or configuration
        self.apiKey = ProcessInfo.processInfo.environment["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"] ?? ""
    }
    
    // MARK: - Public Methods
    
    func deepExplain(for studyItem: StudyItem) async throws -> String {
        let prompt = """
        Please provide a deep, comprehensive explanation of the following:
        
        Question: \(studyItem.question)
        Answer: \(studyItem.answer)
        
        Provide:
        1. A detailed explanation of the concept
        2. Real-world examples
        3. Common misconceptions to avoid
        4. How this relates to other topics
        """
        
        return try await chat(message: prompt)
    }
    
    func generateFlashcardExplanation(question: String, answer: String) async throws -> String {
        let prompt = """
        Explain this study material clearly and comprehensively:
        Q: \(question)
        A: \(answer)
        """
        
        return try await chat(message: prompt)
    }
    
    // MARK: - Private Methods
    
    private func chat(message: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ChatRequest(
            model: "mixtral-8x7b-32768",
            messages: [ChatMessage(role: "user", content: message)],
            maxTokens: 1024,
            temperature: 0.7
        )
        
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw GroqAPIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let chatResponse = try decoder.decode(ChatResponse.self, from: data)
        
        guard let firstChoice = chatResponse.choices.first else {
            throw GroqAPIError.noContentReturned
        }
        
        return firstChoice.message.content
    }
}

// MARK: - Models

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

struct ChatMessage: Codable {
    let role: String // "user" or "assistant"
    let content: String
}

struct ChatResponse: Codable {
    let choices: [ChatChoice]
    let usage: ChatUsage?
}

struct ChatChoice: Codable {
    let message: ChatMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct ChatUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

enum GroqAPIError: LocalizedError {
    case invalidResponse
    case noContentReturned
    case invalidURL
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Groq API"
        case .noContentReturned:
            return "No content returned from API"
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
