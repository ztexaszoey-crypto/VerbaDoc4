import Foundation
import UserNotifications
import Combine
import SwiftUI

// MARK: - NotificationManager
//
// SINGLE-FACADE notification system. Wraps `UNUserNotificationCenter` and
// the existing `StudyReminderService` so callers (SettingsView, root scene
// phase change handlers, post-study-session hooks) have ONE API entry
// point, not three. Designed around three product rules:
//
//   Rule 1 — Permission is NEVER requested during onboarding. We wait for
//            the user to complete their FIRST study session, then prompt
//            in-app with a contextual rationale ("We'll only ping you
//            if you're going to lose your streak"). The OS prompt is only
//            shown after the user taps "Enable" on the rationale screen.
//
//   Rule 2 — The user can toggle every category from SettingsView. Each
//            toggle is persisted in `SharedSettings` (UserDefaults). When
//            the user disables a category, NotificationManager removes
//            its pending requests from the OS queue immediately.
//
//   Rule 3 — Permission denial is not a crash, not a silent skip, not a
//            retry loop. It's surfaced in SettingsView ("Reminders off —
//            tap to open iOS Settings") and the contextual reminders
//            continue to be skipped silently in the background.
//
// Threading:
//
//   * `@MainActor` on all `@Published` state.
//   * UNUserNotificationCenter API is async-friendly; we use the
//     `withCheckedThrowingContinuation` bridge sparingly because Apple's
//     completion-handler API does not throw.
//   * `NotificationManager.shared` is the only public init. `init()`
//     reloads user preferences from `UserDefaults` synchronously and
//     reads the OS permission status asynchronously on first publish.
//
// Persistence keys (UserDefaults):
//   * `notif.streakRemindersEnabled`   Bool   default true
//   * `notif.studyRemindersEnabled`    Bool   default true
//   * `notif.slippingRemindersEnabled` Bool   default true
//   * `notif.permissionRequested`      Bool   default false
//   * `notif.reminderHour`             Int    default 19  (19:00)
//   * `notif.reminderMinute`           Int    default 30
//
// Every key used by the manager is namespaced `notif.` to avoid
// collision with products already on this surface.

@MainActor
final class NotificationManager: ObservableObject {

    /// The single, observable singleton. Inject `NotificationManager.shared`
    /// into Views as `@EnvironmentObject` (or `@ObservedObject`).
    static let shared = NotificationManager()

    // MARK: - Published state

    /// True when the OS has granted `.alert | .badge | .sound`. Updates
    /// after `refreshPermissionStatus()` resolves.
    @Published private(set) var systemPermission: UNAuthorizationStatus = .notDetermined

    /// User-controlled mapping of `[feature: Bool]`. Mirrors the
    /// SettingsView toggles.
    @Published private(set) var settings: NotificationSettings = .defaults

    /// True after the first-study-session permission prompt has been
    /// shown at least once. Used so the contextual prompt doesn't
    /// reappear on every subsequent return to the app.
    @Published private(set) var hasShownRationale: Bool = false

    // MARK: - Private state

    private let center = UNUserNotificationCenter.current()
    private let refreshSubject = PassthroughSubject<Void, Never>()
    /// Serializes `rescheduleAll` callers so consecutive SettingsView
    /// toggles can't interleave on `UNUserNotificationCenter`. Without
    /// this lock, two toggles fired in quick succession produce
    /// `removeAllPending + add` pairs that race on the OS queue.
    private let rescheduleLock = NSLock()

    /// Thread-safe set of identifiers scheduled in the OS queue so we
    /// can bulk-delete on `disableAll()` without re-querying.
    private var knownIdentifiers: Set<String> = [
        NotificationID.streakReminder.rawValue,
        NotificationID.eveningStudy.rawValue,
        NotificationID.slippingCards.rawValue
    ]

    // MARK: - Init

    private init() {
        loadSettingsFromUserDefaults()
        refreshPermissionStatus()
    }

    // MARK: - Notification IDs

    /// Stable string identifiers used in the OS notification queue.
    /// Supplied as `String, rawValue` so ReasoningTest and other
    /// internal debug tools can name them by symbol.
    enum NotificationID: String, CaseIterable {
        case streakReminder   = "verba.evening"            // also used as streak-risk ping at 20:00 when streak >= 3
        case eveningStudy     = "verba.streak"
        case slippingCards    = "verba.slipping"

        /// Reverse lookup for testability (`NotificationID(streakReminder)`).
        init?(_ rawValue: String) {
            for id in Self.allCases where id.rawValue == rawValue {
                self = id
                return
            }
            return nil
        }
    }

    // MARK: - NotificationSettings

    /// User-tunable surface. Persisted to UserDefaults. Each Bool maps
    /// 1:1 to a SettingsView toggle.
    struct NotificationSettings: Codable, Equatable {
        var streakRemindersEnabled:   Bool
        var studyRemindersEnabled:    Bool
        var slippingRemindersEnabled: Bool
        var reminderHour:             Int
        var reminderMinute:           Int

        static let defaults = NotificationSettings(
            streakRemindersEnabled:   true,
            studyRemindersEnabled:    true,
            slippingRemindersEnabled: true,
            reminderHour:             19,
            reminderMinute:           30
        )

        /// Returns the smallest valid hour value. Used in a non-throwing
        /// convenience path so SettingsView sliders can't crash by
        /// exceeding the 0–23 range.
        var validatedHour:   Int { max(0, min(23, reminderHour)) }
        var validatedMinute: Int { max(0, min(59, reminderMinute)) }
    }

    // MARK: - Public API

    /// Refresh the published permission status. Safe to call repeatedly.
    /// Returns nothing — callers can read `systemPermission` synchronously
    /// on the next runloop.
    func refreshPermissionStatus() {
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            Task { @MainActor in
                self.systemPermission = settings.authorizationStatus
            }
        }
    }

    /// Entry point called the moment a study session ends. Decides
    /// whether to show the contextual rationale screen (i.e. the
    /// in-card "we'd like to remind you to keep your streak alive"
    /// view) and — if the user taps "enable" — schedules the OS
    /// permission request.
    ///
    /// Idempotent: calling on every study-session end does not loop
    /// because `hasShownRationale` flips `true` after the first show.
    func handleStudySessionCompleted(
        daysStudiedAlready: Bool,
        streakLengthDays: Int
    ) async {
        guard !hasShownRationale,
              systemPermission == .notDetermined
        else { return }

        hasShownRationale = true
        UserDefaults.standard.set(true, forKey: Keys.permissionRequested)

        // We surface a UI prompt ONLY when the user will actually see
        // value (they have a real streak to protect). If they have no
        // streak and no cards slipping, skip silently — they probably
        // haven't formed the habit yet.
        guard streakLengthDays >= 2 else { return }

        // The SettingsView-driven `presentRationale()` overlay reads
        // `hasShownRationale` to know it's its turn. The actual OS
        // permission request is triggered from a button on that overlay.
        refreshSubject.send()
    }

    /// Request the OS permission. Called ONLY from the in-app rationale
    /// "Enable" button, never on its own. Returns whether the user
    /// granted.
    @discardableResult
    func requestSystemPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await refreshPermissionStatusAfterGrant(granted: granted)
            return granted
        } catch {
            #if DEBUG
            print("[Notifications] requestAuthorization threw: \(error.localizedDescription)")
            #endif
            // Permission API technically not throwing on iOS, but the
            // catch here keeps Swift concurrency happy and we treat
            // throws as "not granted" rather than crashing.
            return false
        }
    }

    /// Persist a settings change. Re-schedules pending reminders to
    /// respect the new toggle (disabled categories = their OS request
    /// is removed). Cheap enough to call on every SettingsView tick.
    func updateSettings(_ newValue: NotificationSettings) async {
        let old = settings
        settings = newValue
        persistSettings(newValue)

        // If user turned off a category, kill the matching OS request.
        if old.streakRemindersEnabled && !newValue.streakRemindersEnabled {
            await removePending(NotificationID.streakReminder)
        }
        if old.studyRemindersEnabled && !newValue.studyRemindersEnabled {
            await removePending(NotificationID.eveningStudy)
        }
        if old.slippingRemindersEnabled && !newValue.slippingRemindersEnabled {
            await removePending(NotificationID.slippingCards)
        }

        // If the user enabled categories, reschedule (StudyReminderService
        // does the time-of-day math).
        if (!old.streakRemindersEnabled && newValue.streakRemindersEnabled)
            || (!old.studyRemindersEnabled && newValue.studyRemindersEnabled)
            || (!old.slippingRemindersEnabled && newValue.slippingRemindersEnabled) {
            await rescheduleAll(
                dueCount: 0,
                slippingCount: 0,
                streakDays: 0,
                todayStudied: false
            )
        }
    }

    /// Disable every reminder category AND remove all pending OS
    /// requests. Used by the SettingsView master toggle and on
    /// account-deletion as belt-and-braces cleanup.
    func disableAll() async {
        settings = NotificationSettings(
            streakRemindersEnabled:   false,
            studyRemindersEnabled:    false,
            slippingRemindersEnabled: false,
            reminderHour:             settings.reminderHour,
            reminderMinute:           settings.reminderMinute
        )
        persistSettings(settings)
        center.removeAllPendingNotificationRequests()
    }

    /// Bridge to the existing `StudyReminderService` so we don't
    /// reimplement the contextual-bodies logic. Pass-through to the
    /// proven engine.
    func rescheduleAll(
        dueCount: Int,
        slippingCount: Int,
        streakDays: Int,
        todayStudied: Bool
    ) async {
        // Belt-and-braces serialization: @MainActor already serializes
        // entry, but the underlying UNUserNotificationCenter calls are
        // not themselves serialized. The lock guarantees a single
        // `removeAllPending + add` sequence is fully complete before
        // the next toggle's body runs.
        rescheduleLock.lock()
        defer { rescheduleLock.unlock() }

        // If user disabled everything in SettingsView, do not schedule.
        guard settings.streakRemindersEnabled
            || settings.studyRemindersEnabled
            || settings.slippingRemindersEnabled
        else { return }

        // We only schedule the categories the user has on. The
        // StudyReminderService schedules a subset (driven by
        // dueCount / streakDays / slippingCount context flags). It
        // ALSO calls `removeAllPendingNotificationRequests` at the top
        // of every invocation, so category-level suppression via
        // `removePending` after the call is the documented behaviour
        // for the case where StudyReminderService schedules something
        // the user has toggled off.
        StudyReminderService.shared.scheduleAll(
            dueCount: dueCount,
            slippingCount: slippingCount,
            streakDays: streakDays,
            todayStudied: todayStudied
        )

        if !settings.streakRemindersEnabled {
            await removePending(NotificationID.streakReminder)
        }
        if !settings.studyRemindersEnabled {
            await removePending(NotificationID.eveningStudy)
        }
        if !settings.slippingRemindersEnabled {
            await removePending(NotificationID.slippingCards)
        }
    }

    /// Returns the user's notification preferences as a static
    /// `URLComponents` query so an external dashboard could read them
    /// (currently only used by SettingsView).
    var settingsSnapshot: String {
        let parts = [
            "streak=\(settings.streakRemindersEnabled ? 1 : 0)",
            "study=\(settings.studyRemindersEnabled ? 1 : 0)",
            "slipping=\(settings.slippingRemindersEnabled ? 1 : 0)",
            "hour=\(settings.validatedHour)",
            "minute=\(settings.validatedMinute)"
        ]
        return parts.joined(separator: "&")
    }

    // MARK: - Internal helpers

    private func removePending(_ id: NotificationID) async {
        center.removePendingNotificationRequests(withIdentifiers: [id.rawValue])
        knownIdentifiers.remove(id.rawValue)
    }

    private func refreshPermissionStatusAfterGrant(granted: Bool) async {
        refreshPermissionStatus()
        if granted {
            await rescheduleAll(
                dueCount: 0,
                slippingCount: 0,
                streakDays: 0,
                todayStudied: false
            )
        }
    }

    // MARK: - Persistence

    private enum Keys {
        static let streakEnabled   = "notif.streakRemindersEnabled"
        static let studyEnabled    = "notif.studyRemindersEnabled"
        static let slippingEnabled = "notif.slippingRemindersEnabled"
        static let reminderHour    = "notif.reminderHour"
        static let reminderMinute  = "notif.reminderMinute"
        static let permissionRequested = "notif.permissionRequested"
    }

    private func loadSettingsFromUserDefaults() {
        let d = UserDefaults.standard
        let defaults = NotificationSettings.defaults

        let streakEnabled = (d.object(forKey: Keys.streakEnabled) as? Bool)
            ?? defaults.streakRemindersEnabled
        let studyEnabled = (d.object(forKey: Keys.studyEnabled) as? Bool)
            ?? defaults.studyRemindersEnabled
        let slippingEnabled = (d.object(forKey: Keys.slippingEnabled) as? Bool)
            ?? defaults.slippingRemindersEnabled

        let hour: Int
        if let stored = d.object(forKey: Keys.reminderHour) as? Int {
            hour = max(0, min(23, stored))
        } else {
            hour = defaults.reminderHour
        }

        let minute: Int
        if let stored = d.object(forKey: Keys.reminderMinute) as? Int {
            minute = max(0, min(59, stored))
        } else {
            minute = defaults.reminderMinute
        }

        settings = NotificationSettings(
            streakRemindersEnabled:   streakEnabled,
            studyRemindersEnabled:    studyEnabled,
            slippingRemindersEnabled: slippingEnabled,
            reminderHour:             hour,
            reminderMinute:           minute
        )
        hasShownRationale = d.bool(forKey: Keys.permissionRequested)
    }

    private func persistSettings(_ s: NotificationSettings) {
        let d = UserDefaults.standard
        d.set(s.streakRemindersEnabled,   forKey: Keys.streakEnabled)
        d.set(s.studyRemindersEnabled,    forKey: Keys.studyEnabled)
        d.set(s.slippingRemindersEnabled, forKey: Keys.slippingEnabled)
        d.set(s.reminderHour,             forKey: Keys.reminderHour)
        d.set(s.reminderMinute,           forKey: Keys.reminderMinute)
    }
}

// MARK: - NotificationRationaleView

/// In-app contextual "Enable Reminders?" view, surfaced by SettingsView
/// when `NotificationManager.hasShownRationale` flips `true`. Pure SwiftUI.
/// Reads `systemPermission` from the manager to decide whether to ask
/// the OS or to surface the "open iOS Settings" path. Lives next to
/// NotificationManager so the rationale text stays in lockstep with
/// the scheduling behaviour.

struct NotificationRationaleOverlay: View {
    @ObservedObject var manager: NotificationManager = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(VerbaTheme.cozyForest)
                .padding(20)
                .background(VerbaTheme.glossCream)
                .clipShape(Circle())
                .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2))

            Text("keep your streak alive")
                .font(VerbaFont.title(size: 24, weight: .black))
                .foregroundStyle(VerbaTheme.cozyForest)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("a short reminder — when cards are due — makes the\ndifference between a 1-day streak and a 30-day streak.")
                .font(VerbaFont.bodyRounded(size: 14, weight: .medium))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Text("we'll only ping you when you're close to losing\nyour streak or when cards are at risk of slipping.")
                    .font(VerbaFont.bodyRounded(size: 12, weight: .regular))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(VerbaTheme.glossCream.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VerbaTheme.oliveBorder.opacity(0.30), lineWidth: 1)
            )

            VStack(spacing: 10) {
                Button {
                    Task {
                        _ = await manager.requestSystemPermission()
                        dismiss()
                    }
                } label: {
                    Text("enable reminders")
                        .font(VerbaFont.syne(.bold, size: 16))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(VerbaTheme.cozyLime)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Text("not now")
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                radius: 0, x: 0, y: 6)
        .padding(28)
    }
}
