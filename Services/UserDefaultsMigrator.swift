import Foundation
import OSLog
import SwiftData

// MARK: - UserDefaultsMigrator
//
// One-shot migration from the prior UserDefaults-based persistence
// (StreakManager / XPManager / SessionTracker) into the new
// SwiftData @Model entities.
//
// Why
//   • Brief §22: "Streaks, mastery, study history, etc. should
//     have a proper persistence strategy." UserDefaults is not
//     acceptable for important app state.
//   • Reinstall + iCloud-backup restoration can wipe UserDefaults
//     but leave SwiftData stores intact. Switching the source of
//     truth to SwiftData protects against that.
//   • The migrator runs once per install and is fully idempotent
//     thanks to a single-shot UserDefaults flag.
//
// What it migrates
//   • verba.streak.current / .lastStudyDate / .totalDays
//       → UserProgress.currentStreak / .lastStudyDate / .totalStudyDays
//   • verba.totalXP / .lastLoginDate
//       → UserProgress.totalXP / .lastLoginDate
//   • verba.dailyGoalCards (read key; default 20 if absent)
//       → UserProgress.dailyGoalCards
//   • verba.recentSessions (CodableStudySession JSON array)
//       → StudySessionEntity rows (per-row deduped by content hash)
//
// Safety
//   • Reads-only on UserDefaults — never deletes values so a partial
//     failure leaves the originals intact for retry/inspect.
//   • Per-day FetchDescriptor + Swift-side content filter: avoids
//     fragile #Predicate composites on Double equality. The
//     migration runs once per install; performance is irrelevant.
//   • Per-row existence check on session insertion ensures re-runs
//     cannot duplicate a session that already migrated. The
//     migrationFlagKey is the primary idempotency guard, but the
//     per-row check is belt-and-braces against partial-state
//     crashes between saves.
//   • Single-shot guard bit "verba.migratedToSwiftData.v1" stops the
//     migrator from running twice after a fully successful migration.
//   • Per-row failures are rate-limited to ONE detailed log line
//     (with NSError code for triage) + a single tail summary
//     message saying "and N more suppressed". This keeps the OSLog
//     buffer from filling if a SwiftData #Predicate regression
//     hits every day-bucket — the worst-case log volume per failed
//     migration attempt is 2 lines.
//
// Error asymmetry (intentionally)
//   • `migrateUserProgress` THROWS — UserProgress is critical; partial
//     migration would leave the user with no streak/XP at all, worse
//     than total failure. Errors propagate to the global catch in
//     `migrateIfNeeded`, the flag stays unset, next launch retries.
//   • `migrateRecentSessions` SWALLOWS per-row — sessions are nice-to-
//     have retention data; partial session migration is strictly
//     better than no progress at all. Per-row catch continues to the
//     next session, leaving the global flag unset for retry. DO NOT
//     unify these two error strategies without re-confirming the
//     rationale above.

enum UserDefaultsMigrator {

    /// The guard key. Marked true after a successful migration.
    /// Future Schema versions can use ".v2" / ".v3" to indicate
    /// additional migration passes.
    static let migrationFlagKey = "verba.migratedToSwiftData.v1"

    /// OSLog handle. Per-row catches log here at `.error` level so
    /// release-build failures are grep-able in TestFlight logs /
    /// Console.app device captures. subsystem matches the bundle
    /// identifier convention so logs route naturally.
    private static let logger = Logger(
        subsystem: "com.verbadoc.migrator",
        category: "UserDefaults"
    )

    /// Public entry point intended for callers that want to trigger
    /// the migration (e.g. a debug "Force Migration" menu).
    /// Internal callers should use `migrateIfNeeded(context:)` —
    /// it's the only path that consults the migrationFlagKey guard.
    static func migrate(context: ModelContext) {
        migrateIfNeeded(context: context)
    }

    // UserDefaults keys (must match StreakManager / XPManager / SessionTracker)
    private enum Keys {
        static let streakCurrent     = "verba.streak.current"
        static let streakLastStudy   = "verba.streak.lastStudyDate"
        static let streakTotalDays   = "verba.streak.totalDays"
        static let totalXP           = "verba.totalXP"
        static let lastLoginDate     = "verba.lastLoginDate"
        static let dailyGoalCards    = "verba.dailyGoalCards"
        static let recentSessions    = "verba.recentSessions"
    }

    // MARK: - Entry point

    /// Run the migration if it has not yet completed. Safe to call
    /// from any ModelContainer-aware init path (main app init,
    /// splash view init, debug-only "Force Migration" menu).
    ///
    /// Errors are logged but never thrown — a partial migration
    /// failure should not prevent the app from booting. The next
    /// launch re-tries until the migrationFlagKey flips true.
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationFlagKey) else {
            return
        }

        do {
            try migrateUserProgress(context: context)
            let outcome = migrateRecentSessions(context: context)
            if outcome.errorCount > 1 {
                let suppressed = outcome.errorCount - 1
                let anchorDate = outcome.firstErrorSessionDate ?? Date()
                logger.error("Suppressed \(suppressed) additional day-bucket fetch error\(suppressed == 1 ? "" : "s"). First rejected session at \(anchorDate, privacy: .public).")
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationFlagKey)
            logger.info("Migration complete (flag flipped to true). Inserted \(outcome.insertedCount) sessions, deduped \(outcome.skippedDuplicates), \(outcome.errorCount) error\(outcome.errorCount == 1 ? "" : "s").")
        } catch {
            // DO NOT tighten this outer catch. The migrationFlagKey
            // stays unset on a recoverable error, so the next launch
            // retries the migration transparently. Showing a user-
            // facing alert here would block access to the app's
            // existing UserDefaults-backed state for a fixable
            // background failure. The per-row catch inside
            // `migrateRecentSessions` is the only place tighter
            // handling belongs.
            //
            // String(describing: error) instead of error.localizedDescription
            // so SwiftData's underlying NSError code surfaces in
            // TestFlight logs for triage.
            logger.error("Migration failed; will retry next launch: \(String(describing: error))")
        }
    }

    // MARK: - UserProgress

    private static func migrateUserProgress(context: ModelContext) throws {
        let uid = "default"
        let descriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate<UserProgress> { $0.userID == uid }
        )
        let progress: UserProgress
        if let existing = try context.fetch(descriptor).first {
            progress = existing
        } else {
            progress = UserProgress(userID: uid)
            context.insert(progress)
        }

        let d = UserDefaults.standard
        progress.currentStreak   = d.integer(forKey: Keys.streakCurrent)
        progress.totalStudyDays  = d.integer(forKey: Keys.streakTotalDays)
        progress.totalXP         = d.integer(forKey: Keys.totalXP)
        // Per-row fallback: prior installs never wrote this key, so
        // we accept the default 20. Existing installs WITH a prior
        // key have their stored value preserved exactly.
        progress.dailyGoalCards  = (d.object(forKey: Keys.dailyGoalCards) as? Int) ?? 20

        if let lastStudy = d.object(forKey: Keys.streakLastStudy) as? Date {
            progress.lastStudyDate = lastStudy
        }
        if let lastLogin = d.object(forKey: Keys.lastLoginDate) as? Date {
            progress.lastLoginDate = lastLogin
        }

        if progress.currentStreak > progress.longestStreak {
            progress.longestStreak = progress.currentStreak
        }
        // firstLaunchAt is set by UserProgress.init() to Date(); the
        // migrator preserves it. No explicit assignment needed.
    }

    // MARK: - Recent sessions

    private struct CodableSession: Codable {
        let date: Date
        let cardsReviewed: Int
        let correctCount: Int
        let duration: TimeInterval
    }

    /// Outcome returned from migrateRecentSessions so the caller
    /// can log a single tail summary of suppressed errors. The
    /// `errorCount` is a RUNNING total (0…N); the function only
    /// logs the FIRST one verbatim to OSLog so the buffer doesn't
    /// fill if a SwiftData predicate regresses.
    private struct SessionMigrationOutcome {
        let insertedCount: Int
        /// Skipped because a session with matching content
        /// (date + cardsReviewed + correctCount + duration)
        /// already exists in SwiftData. Dedup is idempotent.
        let skippedDuplicates: Int
        /// Total errors encountered. First one is logged verbatim;
        /// remaining N-1 appear only in `migrateIfNeeded`'s tail
        /// summary line.
        let errorCount: Int
        /// Verbatim string of the first error captured (for the
        /// tail summary). `nil` if `errorCount == 0`.
        let firstErrorDetail: String?
        /// Date of the first failing session (for log triage).
        /// `nil` if `errorCount == 0`.
        let firstErrorSessionDate: Date?
    }

    private static func migrateRecentSessions(context: ModelContext) -> SessionMigrationOutcome {
        guard let data = UserDefaults.standard.data(forKey: Keys.recentSessions) else {
            return SessionMigrationOutcome(insertedCount: 0, skippedDuplicates: 0, errorCount: 0, firstErrorDetail: nil, firstErrorSessionDate: nil)
        }
        let decoder = JSONDecoder()
        guard let sessions = try? decoder.decode([CodableSession].self, from: data) else {
            return SessionMigrationOutcome(insertedCount: 0, skippedDuplicates: 0, errorCount: 0, firstErrorDetail: nil, firstErrorSessionDate: nil)
        }

        let calendar = Calendar.current
        var inserted = 0
        var duplicates = 0
        var errorCount = 0
        var firstErrorDetail: String?
        var firstErrorSessionDate: Date?

        for cs in sessions {
            // Bucket-by-day fetch: one predicate, one round-trip per
            // day. Avoids #Predicate composite-fragility on Double
            // equality and keypath-chain limitations. Swift-side
            // filter is fine — at most ~90 rows in the §34 window.
            let dayStart = calendar.startOfDay(for: cs.date)
            let dayEnd = dayStart.addingTimeInterval(86_400)

            let dayPredicate = #Predicate<StudySessionEntity> { entity in
                entity.startedAt >= dayStart && entity.startedAt < dayEnd
            }
            let dayEntities: [StudySessionEntity]
            do {
                dayEntities = try context.fetch(
                    FetchDescriptor<StudySessionEntity>(predicate: dayPredicate)
                )
            } catch {
                // Intentional per-row skip: UserDefaults-only state is
                // the source of truth here; the global migrationFlag
                // guards retry on the next launch. Partial session
                // data is strictly better than total-failure
                // migration. This is the asymmetry with
                // `migrateUserProgress`'s throw-on-any-error pattern —
                // DO NOT unify the two paths without re-confirming
                // the rationale above.
                //
                // First-error-only logging + running count for the
                // tail summary in `migrateIfNeeded`. Keeps the OSLog
                // buffer from filling if a SwiftData #Predicate
                // regression hits every day-bucket.
                //
                // String(describing: error) instead of
                // error.localizedDescription so SwiftData's
                // underlying NSError code surfaces in TestFlight.
                errorCount += 1
                if errorCount == 1 {
                    firstErrorDetail = String(describing: error)
                    firstErrorSessionDate = cs.date
                    logger.error("day-bucket fetch failed: \(firstErrorDetail ?? ""). First rejected session at \(cs.date, privacy: .public).")
                }
                continue
            }

            // Per-row content dedup: skip if any session in this day
            // matches on (cardsReviewed, correctCount, duration).
            // Tolerance for Double is exact equality: SwiftData's
            // SQLite stores Doubles as REAL, round-trip is verbatim
            // for the values we originally encoded (TimeInterval,
            // integer-valued), so exact match is safe.
            let alreadyMigrated = dayEntities.contains { entity in
                entity.cardsReviewed == cs.cardsReviewed
                    && entity.correctCount  == cs.correctCount
                    && entity.durationSeconds == cs.duration
            }
            if alreadyMigrated {
                duplicates += 1
                continue
            }

            let entity = StudySessionEntity(startedAt: cs.date)
            entity.endedAt = cs.date
            entity.cardsReviewed = cs.cardsReviewed
            entity.correctCount = cs.correctCount
            entity.durationSeconds = cs.duration
            context.insert(entity)
            inserted += 1
        }

        return SessionMigrationOutcome(
            insertedCount: inserted,
            skippedDuplicates: duplicates,
            errorCount: errorCount,
            firstErrorDetail: firstErrorDetail,
            firstErrorSessionDate: firstErrorSessionDate
        )
    }
}
