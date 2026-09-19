import Foundation
import SwiftData

// MARK: - MisconceptionType
//
// v1 taxonomy — deliberately AP-Bio-sized and extendable. The AI
// classifier (DESIGN.md §5) returns one of these labels + a
// confidence; the CODE decides what happens next. Anything the
// classifier can't label confidently becomes .unknown rather than
// polluting the graph with junk.

enum MisconceptionType: String, Codable, CaseIterable {
    case confusion            // two concepts conflated: NADH vs FADH₂
    case missingPrerequisite  // answer assumes a never-mastered concept
    case overgeneralization   // rule applied beyond its scope
    case sequenceError        // correct pieces, wrong order
    case carelessRead         // misread the prompt; isolated knowledge fine
    case unknown              // not enough signal to classify

    var displayName: String {
        switch self {
        case .confusion:            return "Confusion"
        case .missingPrerequisite:  return "Missing Prerequisite"
        case .overgeneralization:   return "Overgeneralization"
        case .sequenceError:        return "Sequence Error"
        case .carelessRead:         return "Careless Read"
        case .unknown:              return "Unknown"
        }
    }

    /// Short copy for the "🔴 Possible misconception detected" card
    /// (DESIGN.md screen 5).
    var surfaceCopy: String {
        switch self {
        case .confusion:            return "You may be confusing two similar concepts."
        case .missingPrerequisite:  return "This answer assumes a concept you haven't mastered yet."
        case .overgeneralization:   return "You're applying this rule more broadly than it holds."
        case .sequenceError:        return "The pieces are right — the order isn't."
        case .carelessRead:         return "This looks like a misread rather than a knowledge gap."
        case .unknown:              return "We're not sure what went wrong yet."
        }
    }
}

// MARK: - Misconception
//
// A detected pattern on ONE concept, with evidence + resolution
// state. Persisted by the detector; resolved when the retest passes
// N consecutive times (v1: 2). Repeated errors RAISE confidence and
// append evidence — a misconception is a living record, not a flag.

@Model
final class Misconception {
    @Attribute(.unique) var id: String = UUID().uuidString
    var conceptName: String = ""
    var typeRaw: String = MisconceptionType.unknown.rawValue
    var confidence: Double = 0          // 0–1 classifier/evidence confidence
    var evidence: [String] = []         // ReviewRecord IDs / error snapshots
    var relatedConceptNames: [String] = []
    var isResolved: Bool = false
    var firstDetectedAt: Date = Date()
    var lastObservedAt: Date = Date()

    init(
        conceptName: String,
        type: MisconceptionType,
        confidence: Double = 0,
        evidence: [String] = [],
        relatedConceptNames: [String] = []
    ) {
        self.id = UUID().uuidString
        self.conceptName = conceptName
        self.typeRaw = type.rawValue
        self.confidence = confidence
        self.evidence = evidence
        self.relatedConceptNames = relatedConceptNames
        self.isResolved = false
        self.firstDetectedAt = Date()
        self.lastObservedAt = Date()
    }

    // MARK: - Derived

    var type: MisconceptionType {
        get { MisconceptionType(rawValue: typeRaw) ?? .unknown }
        set { typeRaw = newValue.rawValue }
    }

    /// Record another occurrence of the same pattern.
    func reinforce(evidenceID: String, confidenceDelta: Double) {
        self.evidence.append(evidenceID)
        if self.evidence.count > 20 {
            self.evidence = Array(self.evidence.suffix(20))
        }
        self.confidence = min(1.0, self.confidence + confidenceDelta)
        self.lastObservedAt = Date()
    }

    /// Retest passed → mark resolved.
    func resolve() {
        self.isResolved = true
        self.lastObservedAt = Date()
    }
}
