import Foundation
import SwiftData

// MARK: - Concept
//
// Misconception Mapping (see DESIGN.md §3). The knowledge graph:
// each Concept is a node a student can know, misunderstand, or
// miss entirely. `prerequisiteNames` / `relatedConceptNames` are
// STABLE NAME ARRAYS by design — self-referential to-many
// @Relationship pairs on one @Model are the most migration-fragile
// construct SwiftData ships, and name keys are deterministic,
// queryable, and seedable (AP Bio demo). When the graph needs real
// traversal, add a ConceptLink join model — not a self-relationship.
//
// Question metadata lives on the EXISTING StudyItem / MCQuestion
// models (MCQuestion.commonMisconception + whyWrong[distractor]),
// so this model stays purely "the concept".
//
// Relationship to Topic: Topic is the per-Document group label that
// StudyItems hang off (Glycolysis → Krebs hierarchy, master
// aggregates). Concept is the CROSS-document knowledge graph node
// that Misconception Mapping reasons over. They overlap on purpose —
// Topic answers "how is this deck organized?", Concept answers "what
// does this student know across decks?". Do not merge them.

@Model
final class Concept {
    @Attribute(.unique) var id: String = UUID().uuidString
    var name: String = ""
    var subject: String = ""
    var conceptDescription: String = ""
    var prerequisiteNames: [String] = []
    var relatedConceptNames: [String] = []
    /// 1.0 baseline → ~1.5 hardest. Feeds MasteryEngine's difficulty
    /// weighting (harder questions move mastery more).
    var difficulty: Double = 1.0
    var createdAt: Date = Date()

    /// StudentConcept rows tracking mastery of this concept. Inverse
    /// of `StudentConcept.concept` — declared on the collection side
    /// following the Document.topics ↔ Topic.document pattern. No
    /// delete rule: if a Concept is removed, the StudentConcept row
    /// survives (default nullify) so user progress isn't orphaned.
    @Relationship(inverse: \StudentConcept.concept) var studentConcepts: [StudentConcept] = []

    init(
        name: String,
        subject: String,
        conceptDescription: String = "",
        prerequisites: [String] = [],
        related: [String] = [],
        difficulty: Double = 1.0
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.subject = subject
        self.conceptDescription = conceptDescription
        self.prerequisiteNames = prerequisites
        self.relatedConceptNames = related
        self.difficulty = difficulty
        self.createdAt = Date()
        self.studentConcepts = []
    }

    // MARK: - Derived

    /// Convenience lookup for the graph edges. Returns prerequisite
    /// names that are present as their own Concept rows (useful for
    /// "this misconception affects 3 connected concepts" — DESIGN.md
    /// screen 6).
    func linkedConceptNames(from all: [Concept]) -> Set<String> {
        let known = Set(all.map(\.name))
        return Set(prerequisiteNames + relatedConceptNames).intersection(known)
    }
}
