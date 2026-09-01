import Foundation

// MARK: - DailyChallengeManager
//
// Lightweight daily challenge system. No server, no multiplayer.
// One challenge per day, chosen deterministically from a fixed list
// using the day-of-year so it rotates automatically without any backend.
//
// Integration: XPManager.award() calls trackXPAction() on every award.
// That's the only hook needed — no changes to study views.
//
// Persistence: UserDefaults keyed by date string ("yyyy-MM-dd").
// Yesterday's progress is abandoned silently on next launch.

@MainActor
final class DailyChallengeManager: ObservableObject {
    static let shared = DailyChallengeManager()

    // MARK: - Published

    @Published private(set) var todayChallenge: DailyChallenge
    @Published private(set) var progress: Int = 0
    @Published private(set) var isCompleted: Bool = false
    /// True once XP has been awarded for today's challenge. Persisted to avoid double-award
    /// across sessions and tab switches regardless of view lifecycle.
    @Published private(set) var xpAlreadyAwarded: Bool = false

    // MARK: - Challenge Definition

    struct DailyChallenge: Equatable {
        let id: Int
        let title: String
        let description: String
        let goal: Int
        let icon: String
        let type: ChallengeType

        enum ChallengeType {
            case studyCards      // counts .reviewCard XP awards
            case completeSessions // counts .studySession + .quizCompletion awards
        }
    }

    // MARK: - Challenge Catalogue

    private static let catalogue: [DailyChallenge] = [
        .init(id: 0, title: "Warm Up",        description: "Study 10 flashcards",          goal: 10, icon: "flame",              type: .studyCards),
        .init(id: 1, title: "Deep Focus",      description: "Complete a full study session", goal: 1,  icon: "brain",             type: .completeSessions),
        .init(id: 2, title: "Knowledge Sprint", description: "Study 20 flashcards today",   goal: 20, icon: "bolt",              type: .studyCards),
        .init(id: 3, title: "Scholar Mode",    description: "Complete 2 study sessions",    goal: 2,  icon: "books.vertical",    type: .completeSessions),
        .init(id: 4, title: "Sharp Mind",      description: "Study 15 flashcards",          goal: 15, icon: "lightbulb",         type: .studyCards),
        .init(id: 5, title: "Full Commit",     description: "Complete 3 study sessions",    goal: 3,  icon: "checkmark.seal",    type: .completeSessions),
        .init(id: 6, title: "Grind Session",   description: "Study 30 flashcards today",    goal: 30, icon: "figure.run",        type: .studyCards),
    ]

    // MARK: - Init

    /// DateFormatter is expensive; create once and reuse. Static so it survives
    /// the lifetime of the manager and is never recreated on hot paths.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Tracks which calendar day we last loaded state for — used to detect midnight rollovers.
    private var loadedForDay: String = ""

    init() {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        todayChallenge = Self.catalogue[dayOfYear % Self.catalogue.count]
        loadedForDay   = Self.dayFormatter.string(from: Date())
        loadState()
    }

    // MARK: - Midnight Refresh

    /// Call on scenePhase == .active. Resets challenge state when the calendar day has changed,
    /// handling apps that stay in memory overnight without a full relaunch.
    func refreshIfNeeded() {
        let currentDay = Self.dayFormatter.string(from: Date())
        guard currentDay != loadedForDay else { return }
        loadedForDay = currentDay

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        todayChallenge = Self.catalogue[dayOfYear % Self.catalogue.count]
        loadState()
    }

    // MARK: - XP Action Hook
    //
    // Called by XPManager.award() on every XP award.
    // Translates XP actions into challenge progress increments.

    func trackXPAction(_ action: XPAction) {
        guard !isCompleted else { return }
        switch (todayChallenge.type, action) {
        case (.studyCards, .reviewCard):
            incrementProgress(by: 1)
        case (.completeSessions, .studySession),
             (.completeSessions, .quizCompletion):
            incrementProgress(by: 1)
        default:
            break
        }
    }

    // MARK: - Progress

    var progressFraction: Double {
        guard todayChallenge.goal > 0 else { return 0 }
        return min(Double(progress) / Double(todayChallenge.goal), 1.0)
    }

    // MARK: - Private

    private func incrementProgress(by amount: Int) {
        progress = min(progress + amount, todayChallenge.goal)
        saveState()
        if progress >= todayChallenge.goal && !isCompleted {
            isCompleted = true
            saveState()
        }
    }

    // MARK: - Persistence

    private var todayKey: String {
        Self.dayFormatter.string(from: Date())
    }

    private var progressKey:   String { "challenge.progress.\(todayKey)" }
    private var completedKey:  String { "challenge.done.\(todayKey)" }
    private var xpAwardedKey:  String { "challenge.xp.\(todayKey)" }

    private func loadState() {
        progress         = UserDefaults.standard.integer(forKey: progressKey)
        isCompleted      = UserDefaults.standard.bool(forKey: completedKey)
        xpAlreadyAwarded = UserDefaults.standard.bool(forKey: xpAwardedKey)
    }

    private func saveState() {
        UserDefaults.standard.set(progress,         forKey: progressKey)
        UserDefaults.standard.set(isCompleted,      forKey: completedKey)
        UserDefaults.standard.set(xpAlreadyAwarded, forKey: xpAwardedKey)
    }

    /// Called by DailyChallengeCard after awarding XP. Persists the award flag so
    /// view lifecycle resets (tab switches, app foregrounding) never double-award.
    func markXPAwarded() {
        xpAlreadyAwarded = true
        saveState()
    }
}
