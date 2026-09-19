import Foundation
import SwiftData

// MARK: - Achievement
//
// Brief §16 + §2: gamification tied to studying, not novelty.
// Each Achievement row represents ONE achievement the user might
// unlock. Lifetime total count is gated by `unlockedAt != nil`.
//
// Tier system
//   • tier 0 = bronze (single-step unlock; e.g. "first study session")
//   • tier 1 = silver (mid-effort; e.g. "7-day streak")
//   • tier 2 = gold (high-effort; e.g. "100 cards mastered")
//
// Lifecycle
//   • Insert with key + progress = 0 when the achievement is
//     first possible (e.g. after the first deck is created).
//   • Update `progress` on relevant events (range 0…1).
//   • Set `unlockedAt` when progress crosses its threshold.
//   • Never delete; revoked achievements stay archived for
//     future "your journey" timelines.
//
// Storage / Discovery
//   • `key` is `@Attribute(.unique)` so the same achievement is
//     never inserted twice. Lookup helpers (`Achievement.by(key:)`)
//     use a FetchDescriptor with key equality to find a single row.

@Model
final class Achievement {
    @Attribute(.unique) var id: String = UUID().uuidString
    /// Stable string identifier like "first_session",
    /// "streak_7", "cards_mastered_100". Never changes after
    /// first insert; safe to index.
    @Attribute(.unique) var key: String = ""
    var unlockedAt: Date? = nil
    /// 0…1 progress for tiered achievements. 0 if single-step
    /// (unlock-by-completion). Set to 1 when unlockedAt is set.
    var progress: Double = 0
    /// 0 = bronze, 1 = silver, 2 = gold. Used for UI badge color.
    var tier: Int = 0
    var createdAt: Date = Date()

    init(key: String, tier: Int = 0) {
        self.id = UUID().uuidString
        self.key = key
        self.tier = tier
        self.progress = 0
        self.unlockedAt = nil
        self.createdAt = Date()
    }

    // MARK: - Status

    var isUnlocked: Bool { unlockedAt != nil }

    /// Mark an achievement unlocked. Idempotent — calling twice
    /// doesn't reset the unlockedAt timestamp.
    func unlock(now: Date = Date()) {
        if unlockedAt == nil {
            unlockedAt = now
            progress = 1.0
        }
    }
}
