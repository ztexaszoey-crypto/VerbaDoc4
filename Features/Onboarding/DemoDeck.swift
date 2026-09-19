import Foundation
import SwiftData

enum DemoDeck {
    static let title = "The Science of Learning"
    static let seededKey = "verba.demoDeckSeeded"

    private static let cards: [(question: String, answer: String, topic: String)] = [
        ("What is spaced repetition?", "Reviewing material at increasing intervals to exploit the spacing effect — each review session strengthens the memory trace.", "Spacing"),
        ("What is the forgetting curve?", "Ebbinghaus's finding that memories decay exponentially over time without review. The curve shows ~70% forgotten within 24 hours.", "Memory"),
        ("What is active recall?", "Retrieving information from memory without looking at the source. More effective than passive re-reading for long-term retention.", "Recall"),
        ("What is the spacing effect?", "Learning is more durable when study is spread over time rather than massed in one session (cramming).", "Spacing"),
        ("What is interleaving?", "Mixing different topics or problem types within a single study session, which improves discrimination and long-term retention.", "Strategy"),
        ("What is the testing effect?", "Being tested on material strengthens memory more than an equivalent period of re-studying. Also called retrieval practice.", "Recall"),
        ("What is elaborative interrogation?", "A learning technique where you ask 'why' and 'how' questions about facts to create richer, more connected memories.", "Strategy"),
        ("What is desirable difficulty?", "Challenges that slow down learning in the short term but produce stronger long-term memory — like testing yourself before you feel ready.", "Strategy"),
        ("What is the generation effect?", "Information you generate yourself is remembered better than information you passively read.", "Memory"),
        ("What is metacognition?", "Awareness and regulation of your own thinking and learning processes — knowing what you know and don't know.", "Strategy"),
        ("What is distributed practice?", "Breaking study into multiple shorter sessions spread over days or weeks, as opposed to a single long session.", "Spacing"),
        ("What is the primacy effect?", "Items at the beginning of a list are remembered better than those in the middle, due to more rehearsal.", "Memory"),
        ("What is the recency effect?", "Items at the end of a list are remembered better because they are still in working memory.", "Memory"),
        ("What is sleep's role in memory?", "Sleep consolidates memories by replaying experiences and transferring them from the hippocampus to long-term cortical storage.", "Memory"),
        ("What is the contextual interference effect?", "Practicing skills in a varied, interleaved order (high contextual interference) produces better long-term retention than blocked practice.", "Strategy"),
    ]

    @discardableResult
    static func seed(into context: ModelContext) -> Document {
        let doc = Document(title: title, content: "The Science of Learning — a curated deck on memory and study strategy.", sourceType: .text)
        context.insert(doc)

        for card in cards {
            let item = StudyItem(question: card.question, answer: card.answer)
            item.topic = card.topic
            item.document = doc
            doc.studyItems.append(item)
            context.insert(item)
        }

        do {
            try context.save()
        } catch {
            print("[DemoDeck] Failed to save demo deck: \(error)")
        }
        return doc
    }

    static func seedIfNeeded(into context: ModelContext) -> Document? {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return nil }
        let doc = seed(into: context)
        // Only mark seeded after a successful insert (save logs errors but inserts are in-memory)
        UserDefaults.standard.set(true, forKey: seededKey)
        return doc
    }
}
