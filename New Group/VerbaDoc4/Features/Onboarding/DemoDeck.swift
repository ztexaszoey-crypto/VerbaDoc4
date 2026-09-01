import SwiftData
import Foundation

// MARK: - DemoDeck
//
// Hardcoded sample deck seeded on first launch.
// Topic: The Science of Learning — meta, universally relevant, shows the product's value.
//
// Cards are inserted into SwiftData so they live in the user's library after the demo.
// Call DemoDeck.seed(into:) exactly once, guarded by the "hasSeedededDemoDeck" UserDefaults key.

enum DemoDeck {

    static let title = "The Science of Learning"

    // MARK: - Card data

    private static let cards: [(question: String, answer: String, topic: String)] = [
        (
            "What is spaced repetition?",
            "Reviewing material at increasing intervals over time. Each successful recall stretches the next review gap, building a stronger, longer-lasting memory trace.",
            "Spacing"
        ),
        (
            "What is the spacing effect?",
            "Learning is stronger when study sessions are spread out rather than crammed. Distributed practice produces up to 200% better retention than massed practice.",
            "Spacing"
        ),
        (
            "What is active recall?",
            "Actively retrieving information from memory — like answering a flashcard — rather than passively re-reading. It's 2–3× more effective than rereading the same material.",
            "Retrieval"
        ),
        (
            "What is the forgetting curve?",
            "Ebbinghaus's discovery that memory decays exponentially — you forget ~70% of new information within 24 hours without review. Spaced repetition directly counteracts this.",
            "Memory"
        ),
        (
            "What is the testing effect?",
            "Testing yourself on material improves retention more than spending the same time re-studying it. The act of retrieving strengthens the memory more than reading does.",
            "Retrieval"
        ),
        (
            "What is interleaving?",
            "Mixing different subjects or problem types within a single study session. Harder in the moment, but produces stronger long-term learning than blocking one topic at a time.",
            "Strategy"
        ),
        (
            "What does 'desirable difficulty' mean?",
            "Introducing manageable challenges during learning — like retrieval practice or interleaving — improves long-term retention even though it feels harder in the moment.",
            "Strategy"
        ),
        (
            "What is elaborative interrogation?",
            "Asking 'why' and 'how' questions about material as you study. Connects new information to existing knowledge and forces deeper encoding.",
            "Strategy"
        ),
        (
            "What is the generation effect?",
            "Generating an answer yourself — even guessing — produces better retention than reading the answer directly. Struggling to retrieve activates deeper memory consolidation.",
            "Retrieval"
        ),
        (
            "What is chunking?",
            "Grouping related pieces of information into meaningful units. Reduces cognitive load and makes complex material easier to hold in working memory.",
            "Memory"
        ),
        (
            "What is the illusion of knowing?",
            "Feeling like you understand material because it's familiar — when you can't actually retrieve it under pressure. Flashcards expose this gap immediately.",
            "Memory"
        ),
        (
            "What is metacognition?",
            "Thinking about your own thinking. Accurately judging which concepts you truly know vs. which just feel familiar. Strong learners have high metacognitive accuracy.",
            "Strategy"
        ),
        (
            "How long should a focused study session be?",
            "25–45 minutes of focused work, followed by a short break. Beyond 60–90 minutes of continuous study, retention drops significantly due to attentional fatigue.",
            "Strategy"
        ),
        (
            "What role does sleep play in memory?",
            "Sleep consolidates memories — moving them from short-term to long-term storage. Studying before sleep improves next-day retention by up to 30% compared to studying in the morning.",
            "Memory"
        ),
        (
            "What is SRS (Spaced Repetition Software)?",
            "Software that schedules reviews based on your recall performance, showing weak cards more often and strong cards less often. VerbaDoc uses SRS to maximize your study time.",
            "Spacing"
        ),
    ]

    // MARK: - Seeding

    /// Inserts the demo deck into the given SwiftData context.
    /// Returns the created Document so the caller can open it immediately.
    /// Safe to call multiple times — caller should guard with UserDefaults if needed.
    @discardableResult
    static func seed(into context: ModelContext) -> Document {
        let doc = Document(
            title: title,
            content: "Built-in sample deck. The Science of Learning — 15 cards on memory, retrieval, and study strategy.",
            sourceType: .text
        )
        context.insert(doc)

        for card in cards {
            let item = StudyItem(question: card.question, answer: card.answer)
            item.topic    = card.topic
            item.document = doc
            context.insert(item)
        }

        try? context.save()
        return doc
    }

    // MARK: - Guard key

    static let seededKey = "verba.demoDeckSeeded"

    static func seedIfNeeded(into context: ModelContext) -> Document? {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return nil }
        UserDefaults.standard.set(true, forKey: seededKey)
        return seed(into: context)
    }
}
