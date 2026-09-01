import Foundation
import SwiftData

// MARK: - MasteryDecayService
//
// Lifecycle wrapper. Zero scheduling logic lives here.
// Responsibility: figure out how many days have passed, fetch the right cards,
// then hand off entirely to StudyScheduler.applyDecay().
//
// Rule: this file is only allowed to call StudyScheduler. It must not contain
// any formula, multiplier, or mastery mutation of its own.
//
// Called from VerbaDoc4App.onChange(scenePhase == .active).

struct MasteryDecayService {

    private static let lastDecayDayKey = "verba_lastMasteryDecayDay"

    // MARK: - Apply

    @MainActor
    static func apply(context: ModelContext) {
        let calendar  = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        // How many calendar days since we last ran?
        let lastRunStart: Date
        if let stored = UserDefaults.standard.object(forKey: lastDecayDayKey) as? Date {
            lastRunStart = calendar.startOfDay(for: stored)
        } else {
            // First launch — record today so tomorrow we can compute a real gap.
            UserDefaults.standard.set(todayStart, forKey: lastDecayDayKey)
            return
        }

        let daysMissed = calendar.dateComponents([.day], from: lastRunStart, to: todayStart).day ?? 0
        guard daysMissed > 0 else { return }   // already ran today

        // Fetch only cards that have been reviewed at least once. Un-reviewed cards
        // have no SRS history and are never decayed by StudyScheduler.applyDecay —
        // fetching them wastes time and memory on every foreground activation.
        // StudyScheduler still applies its own internal guards (overdue check, etc.).
        let descriptor = FetchDescriptor<StudyItem>(
            predicate: #Predicate { $0.reviewCount > 0 }
        )
        guard let allItems = try? context.fetch(descriptor), !allItems.isEmpty else {
            UserDefaults.standard.set(todayStart, forKey: lastDecayDayKey)
            return
        }

        // Delegate entirely — no logic here
        let modifiedIDs = StudyScheduler.applyDecay(to: allItems, daysMissed: daysMissed)

        try? context.save()
        UserDefaults.standard.set(todayStart, forKey: lastDecayDayKey)

        // Enqueue Firestore sync for every card that decayed.
        // applyDecay now stamps lastModified on mutated cards so the CloudSyncEngine
        // incremental pull cursor (whereField("lastModified", isGreaterThan: cutoff))
        // will include them in the next pull on other devices.
        for id in modifiedIDs {
            CloudSyncEngine.shared.enqueueStudyItemSync(id: id)
        }
    }

    // MARK: - Warmup Candidates

    /// Cards eligible for daily warmup: maintenance + archived cards that are due.
    /// Sorted weakest-first so the most at-risk concepts appear in every warmup.
    static func warmupCandidates(from context: ModelContext, limit: Int = 10) -> [StudyItem] {
        let now = Date()
        let descriptor = FetchDescriptor<StudyItem>(
            predicate: #Predicate {
                ($0.cardLayer == "maintenance" || $0.cardLayer == "archived")
                && $0.nextReviewAt <= now
            },
            sortBy: [SortDescriptor(\.mastery, order: .forward)]
        )
        let results = (try? context.fetch(descriptor)) ?? []
        return Array(results.prefix(limit))
    }
}
