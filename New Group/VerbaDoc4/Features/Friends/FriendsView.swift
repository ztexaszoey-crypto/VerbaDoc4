import SwiftUI
import GameKit
import FirebaseFirestore

// MARK: - FriendsView
//
// Social hub:
//  1. Your stats card — shareable image.
//  2. Leaderboard — Game Center friends ranked by XP.
//  3. Messages — start or continue a DM with any friend via 6-char friend code.
//  4. Invite — share the app.

struct FriendsView: View {
    @EnvironmentObject private var xpManager     : XPManager
    @EnvironmentObject private var streakManager : StreakManager
    @EnvironmentObject private var firebaseManager: FirebaseManager
    @StateObject private var gcManager = GameCenterManager.shared

    @State private var showShareStats  = false
    @State private var statsShareImage : UIImage? = nil
    @State private var showInviteSheet = false
    @State private var showGCProfile   = false
    @State private var selectedPlayer  : GKPlayer? = nil

    // DM flow
    @State private var showNewChat     = false
    @State private var friendCodeInput = ""
    @State private var chatSearch      = false   // true while looking up the friend code
    @State private var chatSearchError : String? = nil
    @State private var pendingChat     : (name: String, convID: String)? = nil

    private let appLink = "https://apps.apple.com/app/verbadoc/id0000000000" // replace with real ID

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        // ── My Stats Card ──────────────────────────────────
                        myStatsSection
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // ── Leaderboard ────────────────────────────────────
                        leaderboardSection
                            .padding(.horizontal, 20)

                        // ── Direct Messages ────────────────────────────────
                        dmSection
                            .padding(.horizontal, 20)

                        // ── Invite ──────────────────────────────────────────
                        inviteSection
                            .padding(.horizontal, 20)

                        Spacer(minLength: 60)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("friends")
                        .font(VerbaFont.syne(.semibold, size: 16))
                        .foregroundStyle(VerbaTheme.ink)
                }
            }
            .task {
                // Authenticate if not yet done; load leaderboard once authenticated.
                if !gcManager.isAuthenticated {
                    gcManager.authenticate()
                }
                // Wait a beat then load — auth may fire async
                try? await Task.sleep(for: .seconds(1))
                await gcManager.loadLeaderboard()
            }
            // Stats share sheet
            .sheet(isPresented: $showShareStats) {
                if let img = statsShareImage {
                    ActivityShareSheet(items: [img])
                        .presentationDetents([.medium, .large])
                }
            }
            // Invite share sheet
            .sheet(isPresented: $showInviteSheet) {
                ActivityShareSheet(items: [
                    "study with me on VerbaDoc 🌿",
                    URL(string: appLink)!
                ])
                .presentationDetents([.medium, .large])
            }
            // Game Center profile sheet
            .sheet(isPresented: $showGCProfile) {
                if let player = selectedPlayer {
                    GCProfileSheet(player: player)
                }
            }
            // New DM sheet — enter friend code
            .sheet(isPresented: $showNewChat) {
                newChatSheet
                    .presentationDetents([.medium])
            }
            // Navigate into chat once friend is found
            .navigationDestination(isPresented: Binding(
                get: { pendingChat != nil },
                set: { if !$0 { pendingChat = nil } }
            )) {
                if let chat = pendingChat {
                    ChatView(friendName: chat.name, convID: chat.convID)
                        .environmentObject(firebaseManager)
                }
            }
        }
    }

    // MARK: - New Chat Sheet

    private var newChatSheet: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()
                VStack(spacing: 24) {
                    VerbaMascot(mood: .happy, size: 64)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text("message a friend")
                            .font(VerbaFont.serif(size: 22))
                            .foregroundStyle(VerbaTheme.ink)
                        Text("ask them for their 6-character friend code — it's in their Friends tab.")
                            .font(VerbaFont.syne(.regular, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 24)

                    // Code input
                    VStack(spacing: 8) {
                        TextField("friend code (e.g. A3F9B2)", text: $friendCodeInput)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: friendCodeInput) { _, v in
                                friendCodeInput = String(v.prefix(6)).uppercased()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(VerbaTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                    .stroke(VerbaTheme.green.opacity(0.30), lineWidth: 1.5)
                            )
                            .padding(.horizontal, 28)

                        if let err = chatSearchError {
                            Text(err)
                                .font(VerbaFont.syne(.regular, size: 12))
                                .foregroundStyle(VerbaTheme.danger)
                        }
                    }

                    Button {
                        Task { await startChat() }
                    } label: {
                        HStack(spacing: 8) {
                            if chatSearch {
                                ProgressView().scaleEffect(0.75).tint(.white)
                            } else {
                                Text("open chat →")
                                    .font(VerbaFont.syne(.medium, size: 15))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(friendCodeInput.count == 6 ? VerbaTheme.green : VerbaTheme.muted.opacity(0.30))
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    }
                    .disabled(friendCodeInput.count < 6 || chatSearch)
                    .padding(.horizontal, 28)
                    .animation(.verbaSnappy, value: friendCodeInput.count)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        friendCodeInput = ""
                        chatSearchError = nil
                        showNewChat     = false
                    }
                    .foregroundStyle(VerbaTheme.muted)
                }
            }
        }
    }

    private func startChat() async {
        chatSearch      = true
        chatSearchError = nil
        // Prevent messaging yourself
        if friendCodeInput == firebaseManager.myFriendCode {
            chatSearchError = "that's your own code 😄"
            chatSearch      = false
            return
        }
        if let friend = await FirebaseManager.shared.findUser(byCode: friendCodeInput) {
            let convID = FirebaseManager.shared.conversationID(with: friend.uid)
            pendingChat    = (name: friend.name, convID: convID)
            friendCodeInput = ""
            chatSearch      = false
            showNewChat     = false
        } else {
            chatSearchError = "no one found with that code — double-check it."
            chatSearch      = false
        }
    }

    // MARK: - My Stats Section

    private var myStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            friendsSectionLabel("your stats")

            ZStack {
                // The card itself — also used as the share image template
                StatsCardView(
                    xp: xpManager.totalXP,
                    rank: xpManager.currentRank,
                    streak: streakManager.currentStreak
                )

                // Share overlay button
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            renderAndShareStats()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .medium))
                                Text("share")
                                    .font(VerbaFont.syne(.medium, size: 12))
                            }
                            .foregroundStyle(VerbaTheme.ink.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                        }
                        .padding(12)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Leaderboard Section

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                friendsSectionLabel("leaderboard · friends")
                Spacer()
                if gcManager.isLoadingLeaderboard {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(VerbaTheme.muted)
                }
                if gcManager.isAuthenticated && !gcManager.isLoadingLeaderboard {
                    Button {
                        Task { await gcManager.loadLeaderboard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                }
            }

            if !gcManager.isAuthenticated {
                gcSignInPrompt
            } else if gcManager.leaderboardEntries.isEmpty && !gcManager.isLoadingLeaderboard {
                leaderboardEmptyState
            } else {
                leaderboardList
            }
        }
    }

    private var gcSignInPrompt: some View {
        VStack(spacing: 16) {
            VerbaMascot(mood: .thinking, size: 56)
            VStack(spacing: 6) {
                Text("sign in to Game Center")
                    .font(VerbaFont.serif(size: 18))
                    .foregroundStyle(VerbaTheme.ink)
                Text("open the Settings app → Game Center → sign in with your Apple ID to see your friends' scores.")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }

    private var leaderboardEmptyState: some View {
        VStack(spacing: 12) {
            VerbaMascot(mood: .thinking, size: 56)
            VStack(spacing: 6) {
                Text("no friends yet")
                    .font(VerbaFont.serif(size: 18))
                    .foregroundStyle(VerbaTheme.ink)
                Text("invite your study group and you'll see their scores here.")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var leaderboardList: some View {
        VStack(spacing: 6) {
            ForEach(gcManager.leaderboardEntries) { entry in
                leaderboardRow(entry)
            }
        }
    }

    private func leaderboardRow(_ entry: GameCenterManager.LeaderboardEntry) -> some View {
        Button {
            // Tap non-local players to open their Game Center profile
            // (from GC profile the user can send a message)
            if !entry.isLocalPlayer, let player = entry.gkPlayer {
                selectedPlayer = player
                showGCProfile  = true
            }
        } label: {
            HStack(spacing: 14) {
                // Rank badge
                Text("#\(entry.rank)")
                    .font(VerbaFont.syne(.bold, size: 13))
                    .foregroundStyle(entry.rank <= 3 ? rankMedalColor(entry.rank) : VerbaTheme.muted)
                    .frame(width: 32, alignment: .leading)

                // Avatar placeholder
                ZStack {
                    Circle()
                        .fill(entry.isLocalPlayer ? VerbaTheme.green.opacity(0.15) : VerbaTheme.ink.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Text(entry.displayName.prefix(1).uppercased())
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(entry.isLocalPlayer ? VerbaTheme.green : VerbaTheme.muted)
                }

                // Name + XP
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(entry.isLocalPlayer ? VerbaTheme.green : VerbaTheme.ink)
                        .lineLimit(1)
                    Text(Rank.rank(for: entry.xp).name.lowercased())
                        .font(VerbaFont.syne(.regular, size: 11))
                        .foregroundStyle(VerbaTheme.muted)
                }

                Spacer()

                // XP score
                Text("\(entry.xp) xp")
                    .font(VerbaFont.syne(.bold, size: 13))
                    .foregroundStyle(entry.isLocalPlayer ? VerbaTheme.green : VerbaTheme.ink)
                    .monospacedDigit()

                if !entry.isLocalPlayer {
                    Image(systemName: "message")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VerbaTheme.muted.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(entry.isLocalPlayer ? VerbaTheme.green.opacity(0.04) : VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(entry.isLocalPlayer ? VerbaTheme.green.opacity(0.20) : VerbaTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(entry.isLocalPlayer)
    }

    private func rankMedalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.78, blue: 0.10)  // gold
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75) // silver
        case 3: return Color(red: 0.80, green: 0.55, blue: 0.28) // bronze
        default: return VerbaTheme.muted
        }
    }

    // MARK: - DM Section

    private var dmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            friendsSectionLabel("messages")

            VStack(spacing: 0) {
                // My friend code — copy on tap
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                            .fill(VerbaTheme.green.opacity(0.10))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(VerbaTheme.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("your friend code")
                            .font(VerbaFont.syne(.medium, size: 14))
                            .foregroundStyle(VerbaTheme.ink)
                        Text(firebaseManager.isReady
                             ? firebaseManager.myFriendCode
                             : "loading…")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(VerbaTheme.green)
                            .tracking(2)
                    }
                    Spacer()
                    if firebaseManager.isReady {
                        Button {
                            UIPasteboard.general.string = firebaseManager.myFriendCode
                            HapticManager.selection()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundStyle(VerbaTheme.muted)
                        }
                    }
                }
                .padding(16)

                Divider().padding(.leading, 56)

                // Start a new DM
                Button { showNewChat = true } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                                .fill(VerbaTheme.blue.opacity(0.10))
                                .frame(width: 36, height: 36)
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(VerbaTheme.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("message a friend")
                                .font(VerbaFont.syne(.medium, size: 14))
                                .foregroundStyle(VerbaTheme.ink)
                            Text("enter their 6-character code to start a chat")
                                .font(VerbaFont.syne(.regular, size: 12))
                                .foregroundStyle(VerbaTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VerbaTheme.muted.opacity(0.5))
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!firebaseManager.isReady)
            }
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )

            Text("share your code with a friend — they enter it to message you directly in the app.")
                .font(VerbaFont.syne(.regular, size: 12))
                .foregroundStyle(VerbaTheme.muted.opacity(0.7))
                .lineSpacing(2)
        }
    }

    // MARK: - Invite Section

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            friendsSectionLabel("invite")

            socialActionRow(
                icon: "person.badge.plus",
                iconColor: VerbaTheme.green,
                title: "invite a friend",
                subtitle: "share VerbaDoc with your study group"
            ) {
                showInviteSheet = true
            }
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
        }
    }

    private func socialActionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                        .fill(iconColor.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(VerbaTheme.ink)
                    Text(subtitle)
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VerbaTheme.muted.opacity(0.5))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Share

    @MainActor
    private func renderAndShareStats() {
        let card = StatsCardView(
            xp: xpManager.totalXP,
            rank: xpManager.currentRank,
            streak: streakManager.currentStreak
        )
        let renderer = ImageRenderer(content: card.frame(width: 360))
        renderer.scale = 3
        if let img = renderer.uiImage {
            statsShareImage = img
            showShareStats  = true
        }
    }

    // MARK: - Helpers

    private func friendsSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(VerbaFont.syne(.semibold, size: 11))
            .foregroundStyle(VerbaTheme.muted)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

// MARK: - StatsCardView
//
// Standalone card used both inline in FriendsView AND rendered-to-image for sharing.
// Keep it self-contained so ImageRenderer captures it correctly.

struct StatsCardView: View {
    let xp     : Int
    let rank   : Rank
    let streak : Int

    @AppStorage("profile.name")         private var profileName      = ""
    @AppStorage("profile.avatarConfig") private var avatarConfigJSON = ""

    private var avatarConfig: AvatarConfig { AvatarConfig.load(from: avatarConfigJSON) }

    var body: some View {
        HStack(spacing: 16) {
            // Custom capybara avatar
            AvatarView(config: avatarConfig, size: 56)

            // Name + rank
            VStack(alignment: .leading, spacing: 4) {
                Text(profileName.isEmpty ? "studying hard 🌿" : profileName)
                    .font(VerbaFont.syne(.semibold, size: 15))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(rank.pondEmoji)
                        .font(.system(size: 13))
                    Text(rank.name.lowercased())
                        .font(VerbaFont.syne(.medium, size: 13))
                        .foregroundStyle(rank.color)
                }
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 8) {
                statChip("\(xp)", label: "xp", color: rank.color)
                statChip("\(streak)", label: "day streak", color: VerbaTheme.orange)
            }
        }
        .padding(18)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(rank.color.opacity(0.22), lineWidth: 1.5)
        )
        // Subtle branding for the share image
        .overlay(alignment: .bottomTrailing) {
            Text("verbadoc")
                .font(VerbaFont.syne(.regular, size: 10))
                .foregroundStyle(VerbaTheme.muted.opacity(0.35))
                .padding(10)
        }
    }

    private func statChip(_ value: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(VerbaFont.syne(.bold, size: 15))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
    }
}

// MARK: - Activity Share Sheet (UIKit bridge)

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Game Center Profile Sheet
//
// GKGameCenterViewController and GKGameCenterControllerDelegate are deprecated
// in the iOS 26 SDK. There is no replacement API for showing a specific player's
// profile programmatically. This implementation is correct and functional on all
// shipping iOS versions (≤ 18). The deprecation warnings below are intentional —
// revisit when Apple provides a successor API.

struct GCProfileSheet: UIViewControllerRepresentable {
    let player: GKPlayer

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let vc = GKGameCenterViewController(player: player)
        vc.gameCenterDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
            vc.dismiss(animated: true)
        }
    }
}
