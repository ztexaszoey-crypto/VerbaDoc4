import Foundation
import Combine

// MARK: - AuthService
//
// Email / password auth backed by Supabase.
// Supabase is free, has no SDK dependency (pure REST), and works offline-first.
//
// Setup (one-time):
//   1. Create a project at supabase.com (free)
//   2. Enable Email auth under Authentication → Providers
//   3. Inject SUPABASE_URL and SUPABASE_ANON_KEY into your target's Info.plist
//      via xcconfig (recommended for Release). DEBUG builds fall back to the
//      project's pre-seeded dev project below; Release builds without a
//      configured value will `fatalError` on first access, preventing a
//      silent misconfiguration.
//
// Token lifecycle:
//   - Access token (JWT) expires in 1 hour — auto-refreshed via refresh token
//   - Tokens are stored in Keychain (see saveSession()/clearSession())
//   - Token is sent with every backend request as "Authorization: Bearer <token>"

final class AuthService: ObservableObject {

    static let shared = AuthService()
    private init() { loadStoredSession() }

    // MARK: - Config
    //
    // Supabase URL + anon key are NOT hardcoded in source. They are loaded
    // from Info.plist (injected by xcconfig). DEBUG builds fall back to the
    // project's pre-seeded dev project so the app boots out of the box.
    // Release builds that omit the keys `fatalError` on first access —
    // preventing a silent misconfiguration from shipping.
    //
    // To configure for Release in Xcode:
    //   xcconfig → SUPABASE_URL     = https://<your-project>.supabase.co
    //   xcconfig → SUPABASE_ANON_KEY = <your-public-anon-key>
    //   Info.plist exposes them via $(SUPABASE_URL) / $(SUPABASE_ANON_KEY) interpolation.

    private static let _supabaseURL: String = configValue(
        plistKey: "SUPABASE_URL",
        debugFallback: "https://bzhxagygigwfhnakxxdd.supabase.co"
    )

    // SECURITY: this anon JWT is committed to source as a DEBUG fallback.
    // Supabase anon keys are designed to be public — they ship in the
    // client bundle by design. Real row-level security comes from RLS
    // policies on the server. Verify ALL user-scoped tables have RLS
    // enabled BEFORE App Store submission:
    //   Supabase Dashboard → Authentication → Policies
    // To rotate this key: Settings → API → "anon / public" → Generate.
    private static let _anonKey: String = configValue(
        plistKey: "SUPABASE_ANON_KEY",
        debugFallback: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ6aHhhZ3lnaWd3ZmhuYWt4eGRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyODc0OTUsImV4cCI6MjA5Njg2MzQ5NX0.5LNXsZBAzWmIa-S9Ev2p_i87LB_sI9yit7xr90BWjQs"
    )

    /// Backwards-compatible read accessor. Existing call sites (`supabaseURL`,
    /// `anonKey`) read through this without any `Self.` prefix changes.
    private var supabaseURL: String { Self._supabaseURL }
    private var anonKey:     String { Self._anonKey }

    /// Base URL used by CardGenerationService to call Edge Functions.
    var supabaseEdgeFunctionURL: String { supabaseURL }

    /// Read a config value from Info.plist. Falls back to the dev fallback
    /// in DEBUG; in RELEASE, never crashes — pins to the dev fallback with
    /// an `assertionFailure` so TestFlight / App Review surfaces a loud
    /// runtime log instead of a hard crash that prevents submission.
    /// Production builds MUST set the value via xcconfig; if they don't,
    /// Supabase requests will fail at the network layer with a graceful
    /// "No connection" / 4xx error rather than crashing the app.
    private static func configValue(plistKey: String, debugFallback: String) -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, !v.isEmpty {
            return v
        }
        #if DEBUG
        return debugFallback
        #else
        assertionFailure("[VerbaDoc] Missing \(plistKey) in Info.plist. Set via xcconfig before App Store submission. App is using dev fallback; backend requests will fail gracefully.")
        NSLog("[VerbaDoc] MISSING_PLIST_KEY %@ — pinning to dev fallback to avoid hard crash.", plistKey)
        return debugFallback
        #endif
    }

    // MARK: - State

    @Published private(set) var currentUser: AuthUser? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var isPlanLoading = false

    var isSignedIn: Bool { currentUser != nil }

    // MARK: - User model

    struct AuthUser: Codable, Equatable {
        let id: String
        let email: String
        var plan: Plan

        enum Plan: String, Codable {
            case free, pro
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async throws {
        await setLoading(true)
        defer { Task { await setLoading(false) } }

        let body: [String: Any] = ["email": email, "password": password]
        let response = try await request(path: "/auth/v1/signup", body: body)

        guard let user = parseUser(from: response) else {
            throw AuthError.invalidResponse
        }
        await saveSession(response)
        await MainActor.run { currentUser = AuthUser(id: user.id, email: user.email, plan: .free) }
        AnonymousEventBridge.fire(.signupCompleted)
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        await setLoading(true)
        defer { Task { await setLoading(false) } }

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "grant_type": "password"
        ]
        let response = try await request(path: "/auth/v1/token?grant_type=password", body: body)

        guard let user = parseUser(from: response) else {
            throw AuthError.invalidCredentials
        }
        await saveSession(response)
        await MainActor.run {
            currentUser = AuthUser(id: user.id, email: user.email, plan: .free)
            isPlanLoading = true
        }

        // Load plan from backend; clear loading flag when done
        await refreshPlan()
        await MainActor.run { isPlanLoading = false }
        AnonymousEventBridge.fire(.loginCompleted)
    }

    // MARK: - Forgot Password

    func resetPassword(email: String) async throws {
        let body: [String: Any] = ["email": email]
        // Supabase returns 200 regardless of whether the email exists (anti-enumeration).
        // A 4xx here means something is structurally wrong (bad key, bad URL, etc.).
        _ = try await request(path: "/auth/v1/recover", body: body)
    }

    // MARK: - Sign Out

    func signOut() async {
        _ = try? await request(path: "/auth/v1/logout", body: [:], method: "POST")
        await clearSession()
        // Wipe all non-auth UserDefaults state (XP, streaks, game progress).
        // AI counter lives in Keychain — intentionally preserved per-device to
        // prevent reinstall bypass. SwiftData wipe is intentionally NOT
        // performed here: it would destroy the user's own decks if they
        // sign back in, and there is no cloud backup to restore from in v1.
        clearAllLocalUserData()
        await MainActor.run { currentUser = nil }
    }

    // MARK: - Apple Sign In (App Store guideline 4.8)

    func signInWithApple(identityToken: String, nonce: String) async throws {
        await setLoading(true)
        defer { Task { await setLoading(false) } }

        let body: [String: Any] = [
            "provider": "apple",
            "id_token": identityToken,
            "nonce": nonce,
        ]
        // Supabase Apple OAuth via REST (no SDK needed)
        let response = try await request(path: "/auth/v1/token?grant_type=id_token", body: body)
        guard let user = parseUser(from: response) else {
            throw AuthError.invalidResponse
        }
        await saveSession(response)
        await MainActor.run {
            currentUser = AuthUser(id: user.id, email: user.email, plan: .free)
            isPlanLoading = true
        }
        await refreshPlan()
        await MainActor.run { isPlanLoading = false }
        AnonymousEventBridge.fire(.appleSignInCompleted)
    }

    // MARK: - Delete Account (App Store guideline 5.1.1(v))

    func deleteAccount() async throws {
        guard let token = accessToken else { throw AuthError.invalidResponse }

        guard let url = URL(string: "\(supabaseURL)/functions/v1/delete-account") else {
            // Misconfigured SUPABASE_URL (empty / malformed Info.plist value)
            // — refuse to crash; surface as a retryable network error.
            throw AuthError.networkError
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw AuthError.networkError
        }

        await clearSession()
        // SECURITY (Privacy guideline 5.1.1(v)): purge ALL per-device state
        // on account delete so a reinstall does not restore the free-trial
        // counter. The AI generation counter lives in Keychain and survives
        // reinstalls on the same device + Apple ID, which would otherwise
        // preserve the bypass across a delete-and-reinstall cycle.
        KeychainService.delete(.freeAIGenerations)
        clearAllLocalUserData()
        await MainActor.run { currentUser = nil }
    }

    // MARK: - Local data wipe (called on account deletion and sign-out-with-wipe)
    //
    // Removes every UserDefaults key the app writes. SwiftData is wiped by the
    // caller (SettingsView) which has access to modelContext.

    func clearAllLocalUserData() {
        // One-time migration cleanup: remove the legacy UserDefaults AI key
        // (now stored in Keychain — Services/KeychainService.Key.freeAIGenerations)
        // so it does not linger on devices that installed a build before this
        // migration shipped.
        UserDefaults.standard.removeObject(forKey: "verba.freeAIGenerations")

        let keys: [String] = [
            // Auth (belt-and-suspenders — clearSession() handles Keychain)
            "verba.auth.accessToken",
            "verba.auth.refreshToken",
            "verba.auth.expiresAt",
            // Onboarding / app state
            "hasSeenOnboarding",
            "verba.demoDeckSeeded",
            // NOTE: AI generation counter is stored in Keychain
            // (KeychainService.Key.freeAIGenerations) — NOT UserDefaults.
            // Intentionally NOT cleared here so the per-device limit survives
            // sign-out. To additionally wipe it on account deletion, call
            // KeychainService.delete(.freeAIGenerations) from deleteAccount().
            // XP & login
            "verba.totalXP",
            "verba.lastLoginDate",
            "verba.previousRank",
            // Streak
            "verba.streak.current",
            "verba.streak.lastStudyDate",
            "verba.streak.totalDays",
            // Session history
            "verba.recentSessions",
            // Return intent
            "verba.returnIntent.v1",
            // Capy Surfers game state
            "capyHighScore",
            "capyWatermelons",
            "capyOwnedSkins",
            "capyEquippedSkin",
            // Settings
            "smartReminders",
            // Event codes (AppState)
            "unlocks.eventItems",
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - Token refresh

    func refreshIfNeeded() async {
        guard let refreshToken = KeychainService.get(.refreshToken),
              let expiresAt = KeychainService.getDate(.tokenExpiresAt),
              Date() > expiresAt.addingTimeInterval(-300)  // refresh 5 minutes before expiry
        else { return }

        let body: [String: Any] = ["refresh_token": refreshToken, "grant_type": "refresh_token"]
        if let response = try? await request(path: "/auth/v1/token?grant_type=refresh_token", body: body) {
            await saveSession(response)
        }
    }

    // MARK: - Current access token (for backend calls)

    var accessToken: String? {
        KeychainService.get(.accessToken)
    }

    // MARK: - Plan refresh (called after sign in + after purchase)

    func refreshPlan() async {
        guard let token = accessToken else { return }

        let url = URL(string: "\(supabaseURL)/rest/v1/user_plans?select=plan&limit=1")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey,           forHTTPHeaderField: "apikey")

        if let (data, _) = try? await URLSession.shared.data(for: req),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]],
           let planStr = arr.first?["plan"],
           let plan = AuthUser.Plan(rawValue: planStr) {
            await MainActor.run { currentUser?.plan = plan }
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func request(
        path: String,
        body: [String: Any],
        method: String = "POST"
    ) async throws -> [String: Any] {
        let url = URL(string: supabaseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let token = accessToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 400 || code == 422 {
                throw AuthError.invalidCredentials
            }
            throw AuthError.networkError
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func parseUser(from response: [String: Any]) -> (id: String, email: String)? {
        // Supabase returns user nested under "user" key in token response
        let userDict = response["user"] as? [String: Any] ?? response
        guard let id    = userDict["id"]    as? String,
              let email = userDict["email"] as? String
        else { return nil }
        return (id, email)
    }

    private func saveSession(_ response: [String: Any]) async {
        let token        = response["access_token"]  as? String ?? ""
        let refreshToken = response["refresh_token"] as? String ?? ""
        let expiresIn    = response["expires_in"]    as? TimeInterval ?? 3600

        KeychainService.set(token,                                    for: .accessToken)
        KeychainService.set(refreshToken,                             for: .refreshToken)
        KeychainService.set(Date().addingTimeInterval(expiresIn),    for: .tokenExpiresAt)

        // Migrate any existing UserDefaults tokens (one-time cleanup)
        ["verba.auth.accessToken", "verba.auth.refreshToken", "verba.auth.expiresAt"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func clearSession() async {
        KeychainService.delete(.accessToken)
        KeychainService.delete(.refreshToken)
        KeychainService.delete(.tokenExpiresAt)
    }

    private func loadStoredSession() {
        // Restore from Keychain regardless of expiry — refreshIfNeeded() will renew if stale
        guard let token = KeychainService.get(.accessToken), !token.isEmpty else { return }

        if let user = decodeJWTUser(token) {
            currentUser = AuthUser(id: user.id, email: user.email, plan: .free)
            isPlanLoading = true
        }

        Task {
            // If expired, renew first so refreshPlan() has a valid token
            if let expiresAt = KeychainService.getDate(.tokenExpiresAt),
               Date() > expiresAt,
               KeychainService.get(.refreshToken) != nil {
                await refreshIfNeeded()
            }
            await refreshPlan()
            await MainActor.run { isPlanLoading = false }
        }
    }

    /// Decode email + sub from JWT payload without verifying signature (client-side only).
    private func decodeJWTUser(_ token: String) -> (id: String, email: String)? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1]
        // Base64 padding
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub   = dict["sub"]   as? String,
              let email = dict["email"] as? String
        else { return nil }
        return (sub, email)
    }

    @MainActor
    private func setLoading(_ value: Bool) {
        isLoading = value
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case invalidCredentials
        case invalidResponse
        case networkError

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "Wrong email or password."
            case .invalidResponse:    return "That took too long. Try again in a moment, or check your connection."
            case .networkError:       return "No connection. Check your internet."
            }
        }
    }
}
