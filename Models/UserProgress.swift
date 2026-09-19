import Foundation
import SwiftData

// MARK: - UserProgress
//
// Brief §22: "Streaks, mastery, study history, etc. should have
// a proper persistence strategy." Do NOT store important state
// exclusively in UserDefaults. User progress lives here in SwiftData.
//
// Identity + scope
//   • One record per logical user, keyed on `userID` (defaults to
//     "default" for the unauthenticated case + the single-account
//     MVP). When AuthService.currentUser.id is non-nil, future PRs
//     rotate userID on sign-in/sign-out to swap the singleton.
//   • `userID` is `@Attribute(.unique)` so `fetchDescriptor` with
//     userID == X returns at most one row.
//   • No inverse relationship on Document/StudyTopic/etc. This is
//     a global singleton for the user; cross-entity aggregation
//     happens in views via `@Query` over the related entities.
//
// Migrated from UserDefaults
//   • verba.streak.current       → currentStreak
//   • verba.streak.lastStudyDate → lastStudyDate
//   • verba.streak.totalDays     → totalStudyDays
//   • verba.totalXP              → totalXP
//   • verba.lastLoginDate        → lastLoginDate
//   • verba.dailyGoalCards       → dailyGoalCards (NEW; default 20)
//
// Aggregates (Brief §10 + §35)
//   • lifetimeCardsReviewed / lifetimeSessionsCompleted /
//     lifetimeCorrectAnswers are incrementally updated by
//     ReviewRecord + StudySessionEntity insert observers. House
//     tab queries these for retention / activation scoring.

@Model
final class UserProgress {
    @Attribute(.unique) var userID: String = "default"

    // MARK: - Streak state (was StreakManager)
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastStudyDate: Date? = nil
    var totalStudyDays: Int = 0

    // MARK: - XP state (was XPManager; Rank derived via Rank.rank(for:))
    var totalXP: Int = 0
    var lastLoginDate: Date? = nil

    // MARK: - User preferences
    /// Default daily goal of 20 cards surfaced in NotificationManager.
    var dailyGoalCards: Int = 20

    // MARK: - Aggregates (incremented on ReviewRecord + StudySessionEntity insert)
    var lifetimeCardsReviewed: Int = 0
    var lifetimeSessionsCompleted: Int = 0
    var lifetimeCorrectAnswers: Int = 0

    // MARK: - Audit
    var firstLaunchAt: Date = Date()

    init(userID: String = "default") {
        self.userID = userID
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastStudyDate = nil
        self.totalStudyDays = 0
        self.totalXP = 0
        self.lastLoginDate = nil
        self.dailyGoalCards = 20
        self.lifetimeCardsReviewed = 0
        self.lifetimeSessionsCompleted = 0
        self.lifetimeCorrectAnswers = 0
        self.firstLaunchAt = Date()
    }

    // MARK: - Derived helpers

    /// Today's-study flag for StreakManager UI parity.
    var todayStudied: Bool {
        guard let last = lastStudyDate else { return false }
        return Calendar.current.startOfDay(for: last)
            == Calendar.current.startOfDay(for: Date())
    }

    /// Convenience: rank enum mirror derived from totalXP. Don't
    /// store this — recomputed at the call site because rank
    /// thresholds change with rank-system redesigns.
    var currentRankRaw: Int {
        // Rank thresholds: 0, 100, 500, 1500, 5000.
        let thresholds = [0, 100, 500, 1500, 5000]
        for i in thresholds.indices.reversed() where totalXP >= thresholds[i] {
            return i
        }
        return 0
    }

    /// Best streak ever achieved (vs. current active streak).
    /// Useful for Home tab "you've made it to 14 days before —
    /// let's beat that!"
    var hasHitLongestStreakToday: Bool {
        guard let last = lastStudyDate else { return false }
        return longestStreak > 1
            && currentStreak == longestStreak
            && Calendar.current.startOfDay(for: last)
                == Calendar.current.startOfDay(for: Date())
    }
}
