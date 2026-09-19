import Foundation

// MARK: - RateLimiter
//
// Per-minute + per-session throttle for high-cost operations (AI
// generation, paid external calls). Closes gap #6 from the Ian Lackey
// "7 Security Holes" article: "LLM calls with no rate limit or spend cap".
//
// Threat model
// ────────────
// A free-tier user could otherwise press the "Generate" button 30
// times within 60 seconds and burn your entire monthly Groq quota in
// a single sitting. The ProGate lifetime counter (max 30 AI gens) only
// catches the long-tail; it doesn't stop in-session spam.
//
// Design
// ──────
// • Counts are stored in UserDefaults as a [Date] array per key.
// • When `consume()` is called, prune timestamps older than `window`,
//   then check `count < limit`. If under → append now, return true.
//   If at/over → return false (caller shows "wait a moment" UI).
// • UserDefaults is fine here: timestamps are *telemetry*, not
//   security-critical. Wiping the array on logout does NOT make the
//   throttle cheat-safe — but a single user shouldn't be able to
//   spend more than `limit` calls per `window` seconds even if the
//   array is wiped. Server-side enforcement (Groq dashboard budget)
//   is the real stop; this layer prevents the UI from letting the
//   user try.

enum RateLimiter {

    // MARK: - Config

    /// Per-minute cap on AI card generation. Free-tier gets the same
    /// cap as Pro so a Pro subscriber can't accidentally hammer either.
    static let aiPerMinute:    Int = 6
    static let aiWindow: TimeInterval = 60

    /// Per-minute cap on password reset + sign-in attempts (defense-
    /// in-depth against credential-stuffing scripts that target the
    /// REST endpoint even though Supabase has its own rate limit).
    static let authPerMinute:  Int = 10
    static let authWindow: TimeInterval = 60

    // MARK: - Storage keys

    private enum Key {
        static let aiTimestamps   = "verba.ratelimit.ai.timestamps"
        static let authTimestamps = "verba.ratelimit.auth.timestamps"
    }

    // MARK: - Consume (atomic check + append)

    /// Returns true if the action is allowed under the rate limit.
    /// Side-effect: writes the new timestamp to UserDefaults.
    static func consume(_ kind: Kind) -> Bool {
        let (limit, window, key) = kind.config
        var timestamps = readTimestamps(key: key)
        let now = Date()
        // Prune anything older than `window` so the count is meaningful.
        timestamps.removeAll { now.timeIntervalSince($0) > window }
        guard timestamps.count < limit else { return false }
        timestamps.append(now)
        writeTimestamps(timestamps, key: key)
        return true
    }

    /// Test remaining capacity without consuming. Used by SettingsView
    /// to show "X of Y remaining" status to power users.
    static func remaining(_ kind: Kind) -> Int {
        let (limit, window, key) = kind.config
        var timestamps = readTimestamps(key: key)
        let now = Date()
        timestamps.removeAll { now.timeIntervalSince($0) > window }
        return max(0, limit - timestamps.count)
    }

    /// Clears all stored timestamps. Call on sign-out so a new user on
    /// the same device isn't artificially throttled by the previous
    /// user's recent activity.
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: Key.aiTimestamps)
        UserDefaults.standard.removeObject(forKey: Key.authTimestamps)
    }

    // MARK: - Kind

    enum Kind {
        case aiGeneration
        case authAttempt

        var config: (limit: Int, window: TimeInterval, defaultsKey: String) {
            switch self {
            case .aiGeneration:
                return (RateLimiter.aiPerMinute, RateLimiter.aiWindow, Key.aiTimestamps)
            case .authAttempt:
                return (RateLimiter.authPerMinute, RateLimiter.authWindow, Key.authTimestamps)
            }
        }
    }

    // MARK: - Private helpers

    private static func readTimestamps(key: String) -> [Date] {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [Double] else {
            return []
        }
        return raw.map { Date(timeIntervalSince1970: $0) }
    }

    private static func writeTimestamps(_ dates: [Date], key: String) {
        let raw = dates.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: key)
    }
}
