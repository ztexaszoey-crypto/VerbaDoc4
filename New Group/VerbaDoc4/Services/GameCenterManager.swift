import Foundation
import GameKit
import UIKit

// MARK: - GameCenterManager
//
// Manages Game Center authentication, XP score submission, and friend leaderboard.
//
// ── SETUP (one-time, per developer) ────────────────────────────────────────────
//  1. Xcode: Project → target → Signing & Capabilities → "+" → Game Center
//  2. App Store Connect → your app → Features → Game Center → Leaderboards → "+"
//     • ID: verbadoc.leaderboard.xp
//     • Title: VerbaDoc XP
//     • Score format: Integer (higher is better)
//     • Score range min: 0
// ───────────────────────────────────────────────────────────────────────────────
//
// The manager degrades gracefully — every @Published bool lets the UI show
// a "sign in to Game Center" prompt instead of crashing.

@MainActor
final class GameCenterManager: ObservableObject {
    static let shared = GameCenterManager()

    // The leaderboard ID registered in App Store Connect (see SETUP above).
    static let leaderboardID = "verbadoc.leaderboard.xp"

    // MARK: - Published State

    @Published private(set) var isAuthenticated    = false
    @Published private(set) var localPlayerName    = ""
    @Published private(set) var localPlayerAvatar: UIImage? = nil
    @Published private(set) var leaderboardEntries: [LeaderboardEntry] = []
    @Published private(set) var isLoadingLeaderboard = false

    // MARK: - Leaderboard Entry

    struct LeaderboardEntry: Identifiable {
        let id          = UUID()
        let rank        : Int
        let displayName : String
        let xp          : Int
        let isLocalPlayer: Bool
        /// GKPlayer reference — used for opening Game Center profile / challenge
        let gkPlayer    : GKPlayer?
    }

    private init() {}

    // MARK: - Authentication

    /// Call once at app launch (RootTabView.onAppear).
    /// Game Center shows its own sign-in sheet when needed.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if GKLocalPlayer.local.isAuthenticated {
                    self.isAuthenticated    = true
                    self.localPlayerName    = GKLocalPlayer.local.displayName
                    self.loadAvatar()
                    // Sync current XP score immediately after sign-in
                    let xp = UserDefaults.standard.integer(forKey: "xp.total")
                    await self.submitScore(xp)
                } else {
                    self.isAuthenticated = false
                    #if DEBUG
                    if let e = error { print("[GameCenter] Auth failed: \(e)") }
                    #endif
                }
            }
        }
    }

    private func loadAvatar() {
        GKLocalPlayer.local.loadPhoto(for: .small) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                self?.localPlayerAvatar = image
            }
        }
    }

    // MARK: - Score Submission

    /// Submits the player's total XP as their leaderboard score.
    /// No-op when Game Center is unavailable — never throws to caller.
    func submitScore(_ xp: Int) async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        do {
            try await GKLeaderboard.submitScore(
                xp,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.leaderboardID]
            )
        } catch {
            #if DEBUG
            print("[GameCenter] Score submit failed: \(error)")
            #endif
        }
    }

    // MARK: - Leaderboard

    /// Loads the friends + local player leaderboard (all-time, top 50).
    func loadLeaderboard() async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID])
            guard let board = boards.first else { return }
            let (local, entries, _) = try await board.loadEntries(
                for: .friendsOnly,
                timeScope: .allTime,
                range: NSRange(location: 1, length: 50)
            )
            var results: [LeaderboardEntry] = []
            if let local {
                results.append(LeaderboardEntry(
                    rank: local.rank,
                    displayName: GKLocalPlayer.local.displayName + " · you",
                    xp: Int(local.score),
                    isLocalPlayer: true,
                    gkPlayer: GKLocalPlayer.local
                ))
            }
            for entry in entries {
                results.append(LeaderboardEntry(
                    rank: entry.rank,
                    displayName: entry.player.displayName,
                    xp: Int(entry.score),
                    isLocalPlayer: false,
                    gkPlayer: entry.player
                ))
            }
            leaderboardEntries = results.sorted { $0.rank < $1.rank }
        } catch {
            #if DEBUG
            print("[GameCenter] Leaderboard load failed: \(error)")
            #endif
        }
    }

}
