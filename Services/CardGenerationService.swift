import Foundation

// MARK: - CardGenerationService
//
// Phase 17 overhaul: the generation pipeline now threads
// `TeacherBlueprint.Difficulty` and a `QualityValidator` report
// through every call. The 4-stage ANALYZE → REPRESENT → GENERATE →
// EVALUATE prompt preamble forces the AI to never copy the source
// PDF, never emit cloze deletions, and never begin a question with
// "According to the document…". A client-side validator
// (`Services/QualityValidator.swift`) is the second line of defence
// for residue that slips past the prompt.
//
// The public surface stays compiled-clean for existing callers.
//
// Routing (all handled server-side in the Supabase Edge Function):
//   1. Gemini 1.5 Flash    (free: 1,500 req/day)   ← primary
//   2. Groq Llama 3        (free: 14,400 req/day)   ← auto-fallback
//   3. Local parser        (offline, always works)  ← flashcards only
//
// The iOS app talks to one endpoint. Provider selection is invisible.

final class CardGenerationService {

    static let shared = CardGenerationService()
    private init() {}

    enum GenerationResult {
        case flashcards([QuizletImporter.Card])
        case multipleChoice([MCQuestion])
        case openAnswer([OpenAnswerQuestion])
        case studyGuide(StudyGuideDocument)
    }

    struct GenerationOutcome {
        public let result: GenerationResult
        public let quality: QualityValidator.Report
        public let difficulty: TeacherBlueprint.Difficulty
        public let directiveSent: String
        public let payloadLength: Int
        public let documentTruncated: Bool
    }

    struct GenerationRequest {
        public let product: GenerationProduct
        public let sourceText: String
        public let title: String
        public let cardCount: Int
        public let difficulty: TeacherBlueprint.Difficulty
        public let runQualityCheck: Bool

        public init(
            product: GenerationProduct,
            sourceText: String,
            title: String,
            cardCount: Int = 20,
            difficulty: TeacherBlueprint.Difficulty = .highSchool,
            runQualityCheck: Bool = true
        ) {
            self.product      = product
            self.sourceText   = sourceText
            self.title        = title
            self.cardCount    = cardCount
            self.difficulty   = difficulty
            self.runQualityCheck = runQualityCheck
        }
    }

    func generate(
        product: GenerationProduct,
        from text: String,
        title: String,
        cardCount: Int = 20
    ) async throws -> GenerationResult {
        let outcome = try await generateOutcome(
            request: GenerationRequest(
                product: product,
                sourceText: text,
                title: title,
                cardCount: cardCount,
                difficulty: .highSchool,
                runQualityCheck: true
            )
        )
        return outcome.result
    }

    func generate(
        product: GenerationProduct,
        from text: String,
        title: String,
        cardCount: Int = 20,
        difficulty: TeacherBlueprint.Difficulty
    ) async throws -> GenerationResult {
        let outcome = try await generateOutcome(
            request: GenerationRequest(
                product: product,
                sourceText: text,
                title: title,
                cardCount: cardCount,
                difficulty: difficulty,
                runQualityCheck: true
            )
        )
        return outcome.result
    }

    func generateOutcome(
        request: GenerationRequest
    ) async throws -> GenerationOutcome {
        let trimmed = request.sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return emptyOutcome(for: request)
        }

        let directive = TeacherBlueprint.directive(
            for: request.product,
            difficulty: request.difficulty
        )
        let aiPayload = directive + "\n\n" + trimmed

        let wasTruncated = trimmed.count > Self.computeSourceBudget(
            forDirectiveLength: directive.count
        )

        if let token = AuthService.shared.accessToken, !token.isEmpty {
            do {
                let result = try await generateViaBackend(
                    product: request.product,
                    text: aiPayload,
                    title: request.title,
                    cardCount: request.cardCount,
                    difficulty: request.difficulty,
                    token: token
                )
                let report = request.runQualityCheck
                    ? qualityReport(for: result, source: trimmed)
                    : QualityValidator.Report(
                        issues: [], verbatimScore: 0,
                        cardsChecked: 0, questionsChecked: 0,
                        openAnswersChecked: 0
                    )
                return GenerationOutcome(
                    result: result,
                    quality: report,
                    difficulty: request.difficulty,
                    directiveSent: directive,
                    payloadLength: aiPayload.count,
                    documentTruncated: wasTruncated
                )
            } catch {
                #if DEBUG
                print("⚠️ [CardGen] Backend failed (\(error)). Falling back.")
                #endif
                if request.product == .flashcards {
                    let offline = flashcardsFromText(trimmed)
                    let report = qualityReport(for: offline, source: trimmed)
                    return GenerationOutcome(
                        result: offline,
                        quality: report,
                        difficulty: request.difficulty,
                        directiveSent: directive,
                        payloadLength: aiPayload.count,
                        documentTruncated: wasTruncated
                    )
                } else {
                    throw error
                }
            }
        }

        if request.product == .flashcards {
            let offline = flashcardsFromText(trimmed)
            return GenerationOutcome(
                result: offline,
                quality: qualityReport(for: offline, source: trimmed),
                difficulty: request.difficulty,
                directiveSent: directive,
                payloadLength: aiPayload.count,
                documentTruncated: wasTruncated
            )
        }
        throw GenerationError.providersUnavailable
    }

    func generate(
        from text: String,
        title: String,
        cardCount: Int = 20,
        useBlueprint: Bool = true
    ) async throws -> [QuizletImporter.Card] {
        let directive = useBlueprint
            ? TeacherBlueprint.directive(for: .flashcards)
            : ""
        let payload = directive.isEmpty ? text : directive + "\n\n" + text
        if let token = AuthService.shared.accessToken, !token.isEmpty {
            do {
                let result = try await generateViaBackend(
                    product: .flashcards,
                    text: payload,
                    title: title,
                    cardCount: cardCount,
                    difficulty: .highSchool,
                    token: token
                )
                guard case .flashcards(let cards) = result else {
                    throw GenerationError.invalidResponse
                }
                return cards
            } catch {
                #if DEBUG
                print("⚠️ [CardGen] Backend failed (\(error)). Re-throwing to caller.")
                #endif
                throw error
            }
        }
        return QuizletImporter.parse(text)
    }

    private func generateViaBackend(
        product: GenerationProduct,
        text: String,
        title: String,
        cardCount: Int,
        difficulty: TeacherBlueprint.Difficulty,
        token: String
    ) async throws -> GenerationResult {

        let base = AuthService.shared.supabaseEdgeFunctionURL
        guard let url = URL(string: "\(base)/functions/v1/generate-cards") else {
            throw GenerationError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 40

        let safeText = PromptSanitizer.wrapContent(
            String(text.prefix(Self.maxPayloadChars))
        )
        let body: [String: Any] = [
            "text":      safeText,
            "title":     title,
            "product":   product.rawValue,
            "cardCount": min(cardCount, 25),
            "difficulty": difficulty.rawValue
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GenerationError.networkError
        }
        if http.statusCode == 503 { throw GenerationError.providersUnavailable }
        guard http.statusCode == 200 else {
            throw GenerationError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenerationError.invalidResponse
        }

        let parsedResult = try parse(product: product, json: json)

        // FIX: cardCount now precedes productType per EventProps init order
        let props = AnalyticsManager.EventProps(
            cardCount: {
                switch parsedResult {
                case .flashcards(let cards):         return cards.count
                case .multipleChoice(let qs):        return qs.count
                case .openAnswer(let qs):            return qs.count
                case .studyGuide(let guide):
                    return guide.keyConcepts.count + guide.timeline.count
                        + guide.peopleTerms.count + guide.causeEffect.count
                }
            }(),
            productType: product.rawValue,
            result: "success"
        )
        await AnalyticsManager.shared.track(.aiGenerationAttempt, props: props)

        let userHash: String
        if let uid = AuthService.shared.currentUser?.id {
            userHash = AnalyticsManager.hash(String(describing: uid))
        } else {
            userHash = "anon"
        }
        let firstGenKey = "verbadoc.firstAIGenerationRequestedFired.\(userHash)"
        if !UserDefaults.standard.bool(forKey: firstGenKey) {
            UserDefaults.standard.set(true, forKey: firstGenKey)
            await AnalyticsManager.shared.track(.firstAIGenerationRequested, props: props)
        }

        return parsedResult
    }

    private func parse(product: GenerationProduct, json: [String: Any]) throws -> GenerationResult {
        switch product {
        case .flashcards:
            guard let arr = json["cards"] as? [[String: Any]], !arr.isEmpty else {
                throw GenerationError.invalidResponse
            }
            let cards = arr.compactMap { dict -> QuizletImporter.Card? in
                guard let q = dict["question"] as? String, !q.isEmpty,
                      let a = dict["answer"]   as? String, !a.isEmpty else { return nil }
                var card = QuizletImporter.Card(question: q, answer: a)
                card.topic = dict["topic"] as? String ?? ""
                return card
            }
            return .flashcards(cards)

        case .multipleChoice:
            let questions = MCQuestion.parseArray(json["questions"])
            guard !questions.isEmpty else { throw GenerationError.invalidResponse }
            return .multipleChoice(questions)

        case .openAnswer:
            let questions = OpenAnswerQuestion.parseArray(json["questions"])
            guard !questions.isEmpty else { throw GenerationError.invalidResponse }
            return .openAnswer(questions)

        case .studyGuide:
            guard let dict = json["guide"] as? [String: Any] else {
                throw GenerationError.invalidResponse
            }
            return .studyGuide(StudyGuideDocument.parse(dict))
        }
    }

    private func qualityReport(
        for result: GenerationResult,
        source: String
    ) -> QualityValidator.Report {
        switch result {
        case .flashcards(let cards):
            return QualityValidator.validate(sourceText: source, cards: cards)
        case .multipleChoice(let qs):
            return QualityValidator.validate(sourceText: source, mcQuestions: qs)
        case .openAnswer(let qs):
            return QualityValidator.validate(sourceText: source, openAnswers: qs)
        case .studyGuide(let guide):
            return QualityValidator.validate(sourceText: source, guide: guide)
        }
    }

    private func flashcardsFromText(_ text: String) -> GenerationResult {
        .flashcards(QuizletImporter.parse(text))
    }

    private func emptyResult(for product: GenerationProduct) -> GenerationResult {
        switch product {
        case .flashcards:     return .flashcards([])
        case .multipleChoice: return .multipleChoice([])
        case .openAnswer:     return .openAnswer([])
        case .studyGuide:     return .studyGuide(StudyGuideDocument.empty)
        }
    }

    private func emptyOutcome(for request: GenerationRequest) -> GenerationOutcome {
        GenerationOutcome(
            result: emptyResult(for: request.product),
            quality: QualityValidator.Report(
                issues: [], verbatimScore: 0,
                cardsChecked: 0, questionsChecked: 0,
                openAnswersChecked: 0
            ),
            difficulty: request.difficulty,
            directiveSent: TeacherBlueprint.directive(
                for: request.product,
                difficulty: request.difficulty
            ),
            payloadLength: 0,
            documentTruncated: false
        )
    }

    private static let totalBudget: Int     = 9_000
    private static let directiveMargin: Int = 50
    private static let minSourceBudget: Int = 1_800

    public static func computeSourceBudget(
        forDirectiveLength directiveChars: Int
    ) -> Int {
        let available = totalBudget - directiveChars - directiveMargin
        return max(available, minSourceBudget)
    }

    public static var maxPayloadChars: Int { totalBudget }

    enum GenerationError: LocalizedError {
        case badURL
        case networkError
        case httpError(Int)
        case invalidResponse
        case providersUnavailable

        var errorDescription: String? {
            switch self {
            case .badURL:               return "Invalid server URL."
            case .networkError:         return "No connection. Check your internet."
            case .httpError(let code):  return "Server error \(code). Try again."
            case .invalidResponse:      return "That took too long. Try again in a moment, or check your connection."
            case .providersUnavailable: return "AI is temporarily unavailable. Try again in a few minutes."
            }
        }
    }

    var apiKey: String {
        get { KeychainService.get(.anthropicApiKey) ?? "" }
        set { _ = newValue }
    }
    var hasApiKey: Bool { false }
}

struct MCQuestion: Codable, Hashable {
    let question:     String
    let options:      [String]
    let correctIndex: Int
    let explanation:  String
    let whyWrong:     [Int: String]
    let topic:        String?
    let commonMisconception: String?

    init(
        question: String,
        options: [String],
        correctIndex: Int,
        explanation: String,
        whyWrong: [Int: String],
        topic: String?,
        commonMisconception: String? = nil
    ) {
        self.question             = question
        self.options              = options
        self.correctIndex         = correctIndex
        self.explanation          = explanation
        self.whyWrong             = whyWrong
        self.topic                = topic
        self.commonMisconception  = commonMisconception
    }

    static func parseArray(_ raw: Any?) -> [MCQuestion] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let q = dict["question"] as? String, !q.isEmpty,
                  let opts = dict["options"] as? [String],
                  opts.count >= 4,
                  let correct = dict["correctIndex"] as? Int,
                  (0..<opts.count).contains(correct) else { return nil }
            let explanation = (dict["explanation"] as? String) ?? ""
            var whyWrong: [Int: String] = [:]
            if let ww = dict["whyWrong"] as? [String: String] {
                for (k, v) in ww {
                    if let idx = Int(k) { whyWrong[idx] = v }
                }
            }
            return MCQuestion(
                question: q,
                options: Array(opts.prefix(4)),
                correctIndex: correct,
                explanation: explanation,
                whyWrong: whyWrong,
                topic: dict["topic"] as? String,
                commonMisconception: dict["commonMisconception"] as? String
            )
        }
    }
}

struct OpenAnswerQuestion: Codable, Hashable {
    let question:       String
    let expectedAnswer: String
    let keyPoints:      [String]
    let topic:          String?
    let idealPoints:      [String]?
    let scoringRubric:    [String: String]?
    let commonMistakes:   [String]?

    init(
        question: String,
        expectedAnswer: String,
        keyPoints: [String],
        topic: String?,
        idealPoints: [String]? = nil,
        scoringRubric: [String: String]? = nil,
        commonMistakes: [String]? = nil
    ) {
        self.question       = question
        self.expectedAnswer = expectedAnswer
        self.keyPoints      = keyPoints
        self.topic          = topic
        self.idealPoints    = idealPoints
        self.scoringRubric  = scoringRubric
        self.commonMistakes = commonMistakes
    }

    static func parseArray(_ raw: Any?) -> [OpenAnswerQuestion] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let q = dict["question"] as? String, !q.isEmpty,
                  let exp = dict["expectedAnswer"] as? String, !exp.isEmpty else { return nil }
            return OpenAnswerQuestion(
                question: q,
                expectedAnswer: exp,
                keyPoints: (dict["keyPoints"] as? [String]) ?? [],
                topic: dict["topic"] as? String,
                idealPoints: dict["idealPoints"] as? [String],
                scoringRubric: dict["scoringRubric"] as? [String: String],
                commonMistakes: dict["commonMistakes"] as? [String]
            )
        }
    }
}

struct StudyGuideDocument: Codable, Hashable {
    struct Concept:  Codable, Hashable { let name: String;        let explanation: String }
    struct Timeline: Codable, Hashable { let date: String;        let event: String }
    struct Person:   Codable, Hashable { let name: String;        let description: String }
    struct Cause:    Codable, Hashable { let cause: String;       let effect: String }
    struct ConfusionPair: Codable, Hashable {
        let conceptA: String
        let conceptB: String
        let clarification: String
    }

    let title:          String
    let overview:       String
    let keyConcepts:    [Concept]
    let timeline:       [Timeline]
    let peopleTerms:    [Person]
    let causeEffect:    [Cause]
    let commonMistakes: [String]
    let examChecklist:  [String]
    let markdownBody: String?
    let quickReviewChecklist: [String]?
    let frequentlyConfusedPairs: [ConfusionPair]?

    init(
        title: String,
        overview: String,
        keyConcepts: [Concept],
        timeline: [Timeline],
        peopleTerms: [Person],
        causeEffect: [Cause],
        commonMistakes: [String],
        examChecklist: [String],
        markdownBody: String?,
        quickReviewChecklist: [String]? = nil,
        frequentlyConfusedPairs: [ConfusionPair]? = nil
    ) {
        self.title                    = title
        self.overview                 = overview
        self.keyConcepts              = keyConcepts
        self.timeline                 = timeline
        self.peopleTerms              = peopleTerms
        self.causeEffect              = causeEffect
        self.commonMistakes           = commonMistakes
        self.examChecklist            = examChecklist
        self.markdownBody             = markdownBody
        self.quickReviewChecklist     = quickReviewChecklist
        self.frequentlyConfusedPairs  = frequentlyConfusedPairs
    }

    static let empty = StudyGuideDocument(
        title: "", overview: "",
        keyConcepts: [], timeline: [], peopleTerms: [],
        causeEffect: [], commonMistakes: [], examChecklist: [],
        markdownBody: nil,
        quickReviewChecklist: nil,
        frequentlyConfusedPairs: nil
    )

    static func parse(_ raw: [String: Any]) -> StudyGuideDocument {
        func pairArr<T>(_ key: String, _ build: (String, String) -> T) -> [T] {
            guard let arr = raw[key] as? [[String: Any]] else { return [] }
            return arr.compactMap { d -> T? in
                guard let a = d.values.first as? String,
                      let b = d.values.dropFirst().first as? String else { return nil }
                return build(a, b)
            }
        }
        let confusedPairs: [ConfusionPair] = {
            guard let arr = raw["frequentlyConfusedPairs"] as? [[String: Any]] else { return [] }
            return arr.compactMap { d in
                guard let a = d["conceptA"] as? String,
                      let b = d["conceptB"] as? String else { return nil }
                return ConfusionPair(
                    conceptA: a,
                    conceptB: b,
                    clarification: (d["clarification"] as? String) ?? ""
                )
            }
        }()
        return StudyGuideDocument(
            title:                    (raw["title"]                    as? String) ?? "",
            overview:                 (raw["overview"]                 as? String) ?? "",
            keyConcepts:              pairArr("keyConcepts",           StudyGuideDocument.Concept.init),
            timeline:                 pairArr("timeline",              StudyGuideDocument.Timeline.init),
            peopleTerms:              pairArr("peopleTerms",           StudyGuideDocument.Person.init),
            causeEffect:              pairArr("causeEffect",           StudyGuideDocument.Cause.init),
            commonMistakes:           (raw["commonMistakes"]           as? [String]) ?? [],
            examChecklist:            (raw["examChecklist"]            as? [String]) ?? [],
            markdownBody:             (raw["markdownBody"]             as? String),
            quickReviewChecklist:     (raw["quickReviewChecklist"]     as? [String]),
            frequentlyConfusedPairs:  confusedPairs
        )
    }
}
