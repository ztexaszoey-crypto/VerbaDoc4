import Foundation
import SwiftData

// MARK: - Topic
//
// Brief §13: "Automatically group related cards into topics.
// Example: Biology → Cellular Respiration → Glycolysis → Krebs Cycle."
//
// Identity model
//   • Each Topic belongs to ONE Document (cascade-delete with it).
//   • `normalizedName` is the lowercase-trimmed key so AI variants
//     ("Cell Division" / "CELL DIVISION" / "cell division") collapse
//     into one Topic.
//   • Two documents with the same surface name produce TWO Topic
//     records; analytics are NOT shared across documents.
//
// Coexistence with legacy string field
//   • StudyItem keeps `var topic: String = ""` as a denormalized
//     name cache for the offline-first path.
//   • `StudyItem.topicRef: Topic?` is the canonical link.
//   • When `topicRef` is nil but `topic` is non-empty, callers fall
//     back to the string field — keeps existing seed data
//     compilable and queryable until the UserDefaults → SwiftData
//     migration runs.

// MARK: - Delete semantics (Brief §21)
//
// The cascade rule lives on the OWING side: `Document.topics` carries
// `.cascade`, so when a Document is deleted all its Topics are deleted
// too. Topic.document is a plain property with `inverse: \Document.topics`
// — SwiftData resolves the bidirectional link and the cascade propagates
// from the parent (Document) into the children (Topics). Brief §21
// satisfied: deleting a Document won't leave orphan Topics behind.

@Model
final class Topic {
    @Attribute(.unique) var id: String = UUID().uuidString
    var name: String = ""
    var normalizedName: String = ""
    var createdAt: Date = Date()

    /// To-one reference back to the Document. Inverse declared here so
    /// SwiftData treats Topic.document ↔ Document.topics as one
    /// bidirectional relationship. Delete rule lives on
    /// `Document.topics` (the owning collection side); this side is
    /// plain so we don't redeclare `.cascade` on both ends (which can
    /// surface a runtime validation warning on some iOS versions).
    var document: Document? = nil

    /// Back-reference to StudyItems that point at this Topic as their
    /// `topicRef`. Inverse declared explicitly so SwiftData treats
    /// Topic.studyItems ↔ StudyItem.topicRef as one bidirectional
    /// relationship. No delete rule: if a Topic is deleted, the
    /// StudyItem.topicRef is nullified (default), preserving the
    /// student's card history when topic metadata is reclassified.
    @Relationship(inverse: \StudyItem.topicRef) var studyItems: [StudyItem] = []

    init(name: String, document: Document? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.normalizedName = Self.normalize(name)
        self.createdAt = Date()
        self.document = document
        self.studyItems = []
    }

    // MARK: - Normalisation (matching key)

    /// Lowercase + collapse all internal whitespace to a single space.
    /// Mirrors `QualityValidator.tokenise(_:)` so AI variants with
    /// extra spaces / newlines / tabs collapse to the same Topic.
    static func normalize(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Aggregates (computed, no stored cache)
    //
    // These are deliberately computed at call-time. They recompute on
    // every read — fine while Topics have ≤50 StudyItems. If a single
    // Topic ever grows past that, hoist to a cached property
    // invalidated by `@Relationship` observation.
    //
    // v1 trade-offs (deliberately deferred to the Home tab integration PR):
    //   • masteryAggregate averages across ALL StudyItems including
    //     zero-mastery new cards. Matches teacher intuition ("how well
    //     does the student know this topic overall") but drags down
    //     topics with mostly-unseen cards. The consumer decides whether
    //     to filter, weight, or keep this initial definition.
    //   • weakRatio counts StudyItems with at least one miss. Brief
    //     §12 specifies REPEATED misses (≥3 for "stuck"). The consumer
    //     adds a separate `stuckRatio` filtered at the ≥3 threshold
    //     before the Home tab wires these in.

    /// Mean mastery across all StudyItems under this topic.
    /// Range: 0…100. Drives Brief §10 + §11 mastery surfacing.
    var masteryAggregate: Double {
        guard !studyItems.isEmpty else { return 0 }
        let total = studyItems.reduce(0.0) { $0 + Double($1.mastery) }
        return total / Double(studyItems.count)
    }

    /// Fraction of StudyItems the student has missed at least once.
    /// Drives Brief §11 weak-topic detection.
    var weakRatio: Double {
        guard !studyItems.isEmpty else { return 0 }
        let missed = studyItems.filter { $0.consecutiveMisses > 0 }.count
        return Double(missed) / Double(studyItems.count)
    }
}
