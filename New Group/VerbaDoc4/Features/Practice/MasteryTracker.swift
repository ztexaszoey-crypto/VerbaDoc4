import Foundation
import SwiftData

/// Tracks per-session mastery state for the VerbaFlow session summary.
///
/// Initialized at session start with a snapshot of each item's mastery score.
/// Computes mastery gained and records which weak concepts were surfaced as gates
/// and answered incorrectly (weak topics hit).
struct MasteryTracker {

    // MARK: - Snapshot

    /// Mastery score per item at session start. Key = item.id
    private let startSnapshot: [String: Int]

    // MARK: - Weak Topics

    /// IDs of items that were presented as gate cards and answered incorrectly.
    /// Used in session summary: "N weak concepts hit."
    private(set) var weakTopicsHit: [String] = []

    // MARK: - Init

    init(items: [StudyItem]) {
        startSnapshot = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.mastery) }
        )
    }

    // MARK: - Record

    /// Record a gate card that the student answered incorrectly.
    /// Deduplicated — the same card is only counted once.
    mutating func recordGateWrong(item: StudyItem) {
        if !weakTopicsHit.contains(item.id) {
            weakTopicsHit.append(item.id)
        }
    }

    // MARK: - Session Delta

    /// Average mastery improvement since session start.
    /// Only compares items that existed at session start — excludes newly added cards
    /// that would dilute the average with their zero mastery scores.
    /// Returns 0 if mastery did not improve (never negative in summary).
    func masteryGained(for items: [StudyItem]) -> Int {
        guard !startSnapshot.isEmpty else { return 0 }
        // Filter to only items that were present when the session began
        let sessionItems = items.filter { startSnapshot[$0.id] != nil }
        guard !sessionItems.isEmpty else { return 0 }
        let startAvg = startSnapshot.values.reduce(0, +) / startSnapshot.count
        let endAvg   = sessionItems.reduce(0) { $0 + $1.mastery } / sessionItems.count
        return max(0, endAvg - startAvg)
    }
}
