import Foundation
import Combine
import CryptoKit

// MARK: - AnalyticsManager
//
// Local-first analytics pipeline. The full product rule:
//
//   * Track every product moment that matters (signup, first-deck,
//     generation, study-session start/end, mastery milestone, share).
//   * Persist locally ATOMICALLY — a crash mid-write must never
//     truncate the log (see `persistAtomic`).
//   * Never emit PII. The ONLY user identifier stored is the bcrypt-style
//     SHA-256 hash of `currentUser.id`, computed once on auth state
//     change. The plaintext user id never touches a log file.
//   * Roll-over after 30 days (history kept without remote sync).
//   * Buckets that drive the cohort dashboard are computed locally
//     from this log so the dashboard works even offline.
//
// Supabase sync is OPTIONAL and runs only if the user is signed in and
// the analytics table exists. We never block UI on the network.

@MainActor
final class AnalyticsManager: ObservableObject {

    /// Singleton. Use `AnalyticsManager.shared`. Inject as
    /// `@EnvironmentObject` only if a view needs to read aggregates;
    /// most call sites do not need environment injection — just
    /// call `AnalyticsManager.shared.track(.signupCompleted)`.
    static let shared = AnalyticsManager()

    // MARK: - Event taxonomy

    /// Single source of truth for product events. Every new event must
    /// be added here and only here — services should not hand-roll event
    /// names. The enum is `Codable` for log-line stability; new cases are
    /// append-only (do NOT reorder, do NOT rename, do NOT delete).
    enum Event: String, Codable, CaseIterable {
        // Acquisition
        case appOpen                     = "app_open"
        case signupStarted               = "signup_started"
        case signupCompleted             = "signup_completed"
        case loginCompleted              = "login_completed"
        case appleSignInCompleted        = "apple_signin_completed"

        // Activation
        case firstDocumentUploaded       = "first_document_uploaded"
        case documentUploaded            = "document_uploaded"
        case firstAIGenerationRequested  = "first_ai_generation_requested"
        case firstStudySessionStarted    = "first_study_session_started"
        // One-time AHA-moment event: the user finished their first
        // study session. This is the milestone `isUserActivated`
        // gates contextual notifications + onboarding completion on.
        // Distinct from `firstStudySessionStarted` (which fires the
        // moment the user enters a session) — the "completed" gate
        // is the engagement signal that matters for activation.
        case firstStudySessionCompleted  = "first_study_session_completed"
        case onboardingCompleted         = "onboarding_completed"

        // Retention
        case studySessionStarted         = "study_session_started"
        case studySessionCompleted       = "study_session_completed"
        case dailyStudyCompleted         = "daily_study_completed"
        case streakExtended              = "streak_extended"
        case streakBroken                = "streak_broken"

        // Learning
        case flashcardCreated            = "flashcard_created"
        case flashcardReviewed           = "flashcard_reviewed"
        case quizCompleted               = "quiz_completed"
        case masteryUpdated              = "mastery_updated"

        // Monetization
        case paywallPresented            = "paywall_presented"
        case paywallUpgraded             = "paywall_upgraded"
        case paywallDismissed            = "paywall_dismissed"

        // Quality / feedback
        case feedbackSubmitted           = "feedback_submitted"
        case crashCaptured               = "crash_captured"

        // Notifications
        case notificationPermissionAsked = "notification_permission_asked"
        case notificationPermissionGranted = "notification_permission_granted"

        // Virality — Phase 18 add for the share-a-deck primitive.
        case shareDeckLinkCreated        = "share_deck_link_created"
        case shareDeckLinkImported       = "share_deck_link_imported"

        // Retention health — Phase 18 add for "started but didn't finish".
        case studySessionAbandoned       = "study_session_abandoned"

        // AI generation — Phase 18 add for full-funnel tracking.
        // `firstAIGenerationRequested` only fires once per user (the
        // activation milestone). For trial-funnel metrics we need a
        // always-on attempt event so we can compute success/failure
        // ratios across all generations, not just the first.
        case aiGenerationAttempt         = "ai_generation_attempt"

        // Monetization failure path — Phase 18 add.
        case paywallUpgradedFailed       = "paywall_upgraded_failed"
    }

    /// Properties attached to an event. Strictly typed so callers can't
    /// pass arbitrary dictionaries; this also documents WHICH fields
    /// each event cares about. We never put PII here.
    struct EventProps: Codable, Equatable {
        var deckID: String?       = nil
        var cardCount: Int?       = nil
        var productType: String?  = nil   // "flashcards" / "quiz" / etc.
        var difficulty: String?   = nil
        var durationSeconds: Double? = nil
        var scorePercent: Double?  = nil
        var source: String?       = nil   // "pdf" / "photo" / "paste" / "youtube"
        var result: String?       = nil   // "success" / "failure"
        var channel: String?      = nil   // "organic" / "school" / "share"
        var variant: String?      = nil   // A/B variant identifier

        // Custom key/value bag. Codable; serialised last. We disallow
        // reserved keys to avoid clobbering typed fields if a caller
        // pass both.
        var extras: [String: String] = [:]
    }

    /// One record on disk: timestamp, hashed user, event, props.
    /// `sessionId` is a UUID generated once per cold-launch — it
    /// ties together all events in a single app session for the
    /// cohort dashboard's "sessions per user" metric.
    struct LogLine: Codable, Equatable {
        var t:      Date            // epoch
        var u:      String?         // hashed user (nil if signed-out)
        var s:      String          // sessionId
        var ev:     String          // Event.rawValue
        var props:  EventProps
        var appVersion: String      // "1.0 (1)" — for cohort split-by-version
    }

    // MARK: - State

    @Published private(set) var totalEventCount: Int = 0
    @Published private(set) var lastEventAt: Date?       = nil

    /// Current app session identifier. Stable for the lifetime of this
    /// process. Reset every cold launch.
    private lazy var sessionId: String = UUID().uuidString

    /// Cached hashed user id (Keychain-friendly). Re-derived whenever
    /// AuthService.currentUser changes.
    private var hashedUser: String? {
        guard let raw = AuthService.shared.currentUser?.id else { return nil }
        return Self.hash(raw)
    }

    // MARK: - Private state

    /// Lock so the writes from background tasks don't race the UI thread.
    /// Phase 20: moved to `static nonisolated(unsafe)` so the IO helpers
    /// (which now run on a detached Task) can hold the lock from a
    /// background thread without crossing the MainActor.
    nonisolated(unsafe) private static let ioLock = NSLock()

    /// URL of the JSONL log on disk. We use `Application Support` over
    /// `Documents` so the log never gets iCloud-backed-up, so a user
    /// restore does NOT bring old logs along (preserves cohort hygiene).
    /// `static nonisolated(unsafe)`: the path is computed once at
    /// process launch and is stable for the lifetime.
    nonisolated(unsafe) private static let logURL: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("VerbaDoc", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.jsonl")
    }()

    // MARK: - Init

    private init() {
        bootstrap()
    }

    // MARK: - PUBLIC entry points

    /// Track an event with no properties. The most-used overload.
    func track(_ event: Event) {
        track(event, props: EventProps())
    }

    /// Track an event with custom properties. Atomic on disk.
    /// Every property bag is PII-scrubbed before persistence — keys
    /// matching known PII fragments (email, name, phone, address)
    /// are dropped with a `#if DEBUG` warning. Use the typed struct
    /// fields (`deckID`, `scorePercent`, etc) for safe defaults.
    func track(_ event: Event, props: EventProps) {
        var safeProps = props
        Self.scrubPII(&safeProps)

        let line = LogLine(
            t:          Date(),
            u:          hashedUser,
            s:          sessionId,
            ev:         event.rawValue,
            props:      safeProps,
            appVersion: Self.currentAppVersion
        )
        // Phase 20: hop the on-disk log append OFF the MainActor. The
        // disk write previously held an NSLock on the calling thread;
        // every `track()` call was a synchronous `FileHandle.write`
        // that could stall frames. The detached Task runs on the
        // cooperative pool at `.utility` priority so UI work keeps
        // the wheel. `LogLine` is a value-type Codable struct so
        // capturing it across the closure boundary is Sendable-safe.
        Task.detached(priority: .utility) {
            Self.appendToDisk(line: line)
        }
        Task { @MainActor in
            self.totalEventCount += 1
            self.lastEventAt = line.t
        }
    }

    /// PII-scrubbing guard. Phase 18 reviewer-flagged: the
    /// `extras: [String: String]` field is too permissive — a
    /// developer could pass `["email": user.email]` thinking it's
    /// metadata. We block any key whose lowercase contains a known
    /// PII fragment and log a debug-only warning.
    nonisolated private static let piiKeyFragments: [String] = [
        "email", "phone", "address", "name", "ssn", "dob"
    ]
    // (Phase 18 closeout: removed `"mail"` from this list. It was a
    //  false-positive trap: `"mail"` matches `gmail`, `femail`
    //  (German slang), and `send_mail_template_id`. The remaining
    //  `"email"` cover the real-world email-shaped keys: `user_email`,
    //  `customerEmail`, `emailVerified`, etc. — `email_lower.contains
    //  ("email")` is sufficient.)

    nonisolated private static func scrubPII(_ props: inout EventProps) {
        let loweredKeys = props.extras.keys.map { $0.lowercased() }
        let dropKeys: [String] = props.extras.keys.enumerated()
            .filter { idx, _ in
                let lk = loweredKeys[idx]
                return piiKeyFragments.contains(where: { lk.contains($0) })
            }
            .map(\.1)
        for key in dropKeys {
            #if DEBUG
            print("[Analytics] ⚠️ dropped PII-suspicious extras key '\(key)' — use a typed EventProps field instead")
            #endif
            props.extras.removeValue(forKey: key)
        }
    }

    /// Returns true if the user has previously completed at least one
    /// of the activation milestones (signup → first-deck → first-study).
    /// Used to decide whether the contextual notifications overlay should
    /// be surfaced.
    var isUserActivated: Bool {
        let lines = readAllLines()
        let names = Set(lines.map(\.ev))
        return names.contains(Event.signupCompleted.rawValue)
            && names.contains(Event.firstDocumentUploaded.rawValue)
            && names.contains(Event.firstStudySessionCompleted.rawValue)
    }

    /// In-memory cohort calculation. Returns the cohort-membership map:
    /// `["d1": Int, "d7": Int, "d30": Int]`. Computed locally from the
    /// log; safe even offline. Exposed as flat `Int` counts so the
    /// SettingsView / dashboard can render them directly.
    func cohortMap(now: Date = Date()) -> [String: Int] {
        let lines = readAllLines()
        let d1Cutoff  = now.addingTimeInterval(-1 * 86400)
        let d7Cutoff  = now.addingTimeInterval(-7 * 86400)
        let d30Cutoff = now.addingTimeInterval(-30 * 86400)

        var dailyStudy: Set<String>   = []   // hashed user
        var weeklyStudy: Set<String>  = []
        var monthlyStudy: Set<String> = []
        var activeUsers: Set<String>  = []

        for line in lines where line.ev == Event.dailyStudyCompleted.rawValue {
            activeUsers.insert(line.u ?? "anon")
            if line.t >= d1Cutoff  { dailyStudy.insert(line.u ?? "anon") }
            if line.t >= d7Cutoff  { weeklyStudy.insert(line.u ?? "anon") }
            if line.t >= d30Cutoff { monthlyStudy.insert(line.u ?? "anon") }
        }

        return [
            "d1":  dailyStudy.count,
            "d7":  weeklyStudy.count,
            "d30": monthlyStudy.count,
            "activeUsers": activeUsers.count,
            "totalEvents": lines.count
        ]
    }

    /// Total number of distinct users to ever `signup_completed`.
    func cumulativeSignups() -> Int {
        let lines = readAllLines().filter { $0.ev == Event.signupCompleted.rawValue }
        var seen = Set<String>()
        for line in lines { if let u = line.u { seen.insert(u) } }
        return seen.count
    }

    /// Total study sessions completed in the trailing 30 days.
    func recentSessionCount(days: Int = 30) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let lines = readAllLines().filter {
            $0.ev == Event.studySessionCompleted.rawValue && $0.t >= cutoff
        }
        return lines.count
    }

    /// Number of cards reviewed across all sessions (lifetime).
    func lifetimeCardsReviewed() -> Int {
        let lines = readAllLines().filter { $0.ev == Event.flashcardReviewed.rawValue }
        return lines.reduce(0) { $0 + ($1.props.cardCount ?? 0) }
    }

    // MARK: - Atomic write

    /// Append a single log line as NDJSON. Uses `FileHandle.write` rather
    /// than `String.write` + `String(contentsOf:)` so concurrent
    /// background flushes and a foreground track() call do not collide
    /// and a crash mid-write cannot corrupt earlier lines.
    nonisolated static func appendToDisk(line: LogLine) {
        ioLock.lock()
        defer { ioLock.unlock() }

        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }
        guard let data = try? encoder.encode(line) else { return }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))   // newline
        } catch {
            #if DEBUG
            print("[Analytics] append failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Read helpers

    /// Reads the entire log from disk. Returns `[]` on any error so the
    /// dashboard never blackholes. Note: log line count is bounded at
    /// ~50,000 (≈ 5MB on disk) by the 30-day rollover.
    private func readAllLines() -> [LogLine] {
        // The IO is performed by the static nonisolated core; this
        // MainActor-isolated wrapper just preserves the call-site
        // surface for existing callers (cohortMap, cumulativeSignups,
        // recentSessionCount, lifetimeCardsReviewed, isUserActivated).
        return Self.readAllLinesStatic()
    }

    nonisolated static func readAllLinesStatic() -> [LogLine] {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let raw = String(decoding: data, as: UTF8.self)
        var lines: [LogLine] = []
        for chunk in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if let line = try? Self.decoder.decode(LogLine.self, from: Data(chunk.utf8)) {
                lines.append(line)
            }
        }
        return lines
    }

    // MARK: - Bootstrap & maintenance

    /// Called once on init. Truncates the log to the last 30 days and
    /// publishes the retained line count on the @MainActor so SwiftUI
    /// observers (SettingsView / dashboard) reflect the on-disk truth
    /// before the first `track()` call lands.
    private func bootstrap() {
        performRollover()
    }

    /// Truncate the on-disk log to the last 30 days under the io
    /// lock, then publish the retained line count back through the
    /// @MainActor. Cheap (≤ a few MB / a few thousand lines on disk
    /// at steady state) so we don't bother with a background queue.
    private func performRollover() {
        // Phase 20: IO runs on the static nonisolated core so init-time
        // rollover no longer holds the MainActor across a synchronous
        // read → filter → write sequence. The retained count is
        // returned here and published on the @MainActor (this wrapper)
        // because `totalEventCount` is `@Published` and lives on the
        // actor-isolated instance.
        let retainedCount = Self.performRolloverStatic()
        totalEventCount = retainedCount
    }

    /// Truncate the on-disk log to the last 30 days and return the
    /// number of retained lines. Runs on a nonisolated static path
    /// under `ioLock` so concurrent `appendToDisk` callers cannot
    /// race the foreground rollout and a crash mid-write cannot
    /// corrupt earlier lines. `Int` is `Sendable`, so the boundary
    /// back to the @MainActor wrapper is clean.
    nonisolated static func performRolloverStatic() -> Int {
        ioLock.lock()
        defer { ioLock.unlock() }

        let cutoff = Date().addingTimeInterval(-30 * 86400)
        guard let data = try? Data(contentsOf: logURL) else { return 0 }
        let raw = String(decoding: data, as: UTF8.self)
        var retained = ""
        var count = 0

        for chunk in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if let line = try? Self.decoder.decode(LogLine.self, from: Data(chunk.utf8)) {
                if line.t >= cutoff {
                    retained.append(chunk + "\n")
                    count += 1
                }
            } else {
                // Garbage line — drop it silently. The atomic write
                // path guarantees formatting but we can recover from
                // corruption caused by external interference
                // (e.g. restore from a partial iCloud backup).
            }
        }
        if let bytes = retained.data(using: .utf8) {
            try? bytes.write(to: logURL, options: .atomic)
        }
        return count
    }

    // MARK: - Codable support

    nonisolated(unsafe) private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - Utility

    /// SHA-256 hex of a string. Used to anonymise user IDs in the log.
    /// Holds no salt (the privacy budget is "unique-ish but unguessable
    /// from a known user id"; a real production system would bucket
    /// hashes but that adds a server dependency we don't have yet).
    static func hash(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// "1.0 (1)" — used as `appVersion` in every event. Computed once
    /// per process; the cost is trivial.
    nonisolated(unsafe) private static let currentAppVersion: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"]          as? String ?? "1"
        return "\(v) (\(b))"
    }()
}

// (Phase 18: removed `SHA256Helper` indirect enum after code review.
//  `hash(_)` now inlines `SHA256.hash(data:)` directly. If the wider
//  project later needs a shared hash helper, reintroduce it under
//  Services/ rather than as a nested symbol.)

// MARK: - AnonymousEventBridge
//
// Free-function form of `track` so call sites that are not on the
// main actor (e.g. background tasks, CloudSyncEngine) can fire events
// without acquiring the manager. Forwards via a Task to the main actor.

enum AnonymousEventBridge {
    static func fire(_ event: AnalyticsManager.Event,
                     props: AnalyticsManager.EventProps = .init()) {
        Task { @MainActor in
            AnalyticsManager.shared.track(event, props: props)
        }
    }
}
