import SwiftUI
import SwiftData
import RevenueCat
import RevenueCatUI

// MARK: - SettingsView (FELIwS pastel-green migration)
//
// Every flat white card becomes a sticky-note `cozyBlockCard()` cream
// chip. Every "card with subtle shadow" becomes a chunky 3D chip.
// Inline stat strips, weekly bar chart, deck-report rows: all on
// cozy chassis. Destructive sign-out / delete-account buttons
// switch to chunky cream chips so the entire profile screen feels
// handcrafted.

struct SettingsView: View {
    @AppStorage("smartReminders") private var smartReminders = true
    @AppStorage("dailyGoal")      private var dailyGoal      = 20   // Phase 20: user-editable daily-goal tie-in
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var purchases: PurchaseService
    @ObservedObject private var gate = ProGate.shared
    @Environment(\.modelContext) private var modelContext
    @Query private var documents: [Document]

    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount      = false
    @State private var deleteError: String?   = nil
    @State private var showPaywall            = false
    @State private var showCustomerCenter     = false

    private var activeDocuments: [Document] { documents.filter { !$0.isArchived } }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        CozyBackdrop {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {

                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    proStatusBanner
                        .padding(.horizontal, 18)

                    rankCard
                        .padding(.horizontal, 18)

                    statRow
                        .padding(.horizontal, 18)

                    weeklyActivityCard
                        .padding(.horizontal, 18)

                    if !activeDocuments.isEmpty {
                        deckReportCard
                            .padding(.horizontal, 18)
                    }

                    settingsBlock
                        .padding(.horizontal, 18)

                    accountActions
                        .padding(.horizontal, 18)

                    legalRow

                    Spacer(minLength: 80)
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showCustomerCenter) { CustomerCenterView() }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete My Account", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    do {
                        try await AuthService.shared.deleteAccount()
                        try modelContext.delete(model: Document.self)
                        try modelContext.save()
                        await purchases.logOut()
                    } catch {
                        // SECURITY: never leak `error.localizedDescription` to UI.
                        // FriendlyErrorMapper returns user-safe copy that does not
                        // expose Supabase URLs, Postgres column names, or stack-
                        // trace hints for the auth.users DELETE call.
                        deleteError = FriendlyErrorMapper.message(for: error, in: .auth)
                    }
                    isDeletingAccount = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and all data. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("you")
                    .font(VerbaFont.title(size: 28, weight: .black))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text("your profile, your mastery")
                    .font(VerbaFont.bodyRounded(size: 13, weight: .medium))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
            Spacer()
            VerbaMascot(mood: .calm, size: 48)
                .padding(6)
                .background(
                    ZStack {
                        Circle().fill(VerbaTheme.glossCream)
                        Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                    }
                )
                .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.25),
                        radius: 0, x: 0, y: 4)
        }
    }

    // MARK: - Pro Status Banner

    @ViewBuilder
    private var proStatusBanner: some View {
        if gate.isPro {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .frame(width: 32, height: 32)
                    .background(
                        ZStack {
                            Circle().fill(VerbaTheme.glossCream)
                            Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                        }
                    )
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.20),
                            radius: 0, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("VerbaDoc Pro")
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Text("All features unlocked")
                        .font(VerbaFont.syne(.medium, size: 12))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }
                Spacer()
                ClayStatusChip("manage", icon: "gearshape.fill", variant: .cream)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(VerbaTheme.cozySage.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                    .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                    radius: 0, x: 0, y: 5)
        } else {
            Button {
                AnalyticsManager.shared.track(.paywallPresented)
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .frame(width: 32, height: 32)
                        .background(
                            ZStack {
                                Circle().fill(VerbaTheme.glossCream)
                                Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                            }
                        )
                        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.20),
                                radius: 0, x: 0, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free Plan")
                            .font(VerbaFont.syne(.bold, size: 15))
                            .foregroundStyle(VerbaTheme.cozyForest)
                        Text("\(ProGate.Limit.maxAIGenerations - gate.aiGenerationsUsed) AI gens left · \(ProGate.Limit.maxDecks) deck limit")
                            .font(VerbaFont.syne(.medium, size: 12))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                    Spacer()
                    ClayStatusChip("upgrade →", icon: "arrow.up.right", variant: .mint)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(VerbaTheme.cozySage)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                        .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                )
                .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                        radius: 0, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Rank Card

    private var rankCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: rankIconName(for: xpManager.currentRank))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .frame(width: 52, height: 52)
                    .background(
                        ZStack {
                            Circle()
                                .fill(VerbaTheme.cozyLime)
                            Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                        }
                    )
                    .overlay(
                        Circle().inset(by: 2)
                            .stroke(VerbaTheme.glossCream.opacity(0.80), lineWidth: 1.2)
                    )
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                            radius: 0, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(xpManager.currentRank.name)
                        .font(VerbaFont.syne(.bold, size: 18))
                        .foregroundStyle(xpManager.currentRank.color)
                    Text("\(xpManager.totalXP) XP total")
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                }
                Spacer()
            }

            if let nextRank = nextRank() {
                let progress = Double(xpManager.totalXP - xpManager.currentRank.xpThreshold)
                    / Double(nextRank.xpThreshold - xpManager.currentRank.xpThreshold)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("progress to \(nextRank.name)")
                            .font(VerbaFont.syne(.bold, size: 11))
                            .tracking(1.0)
                            .textCase(.uppercase)
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        Spacer()
                        Text("\(xpManager.totalXP) / \(nextRank.xpThreshold) XP")
                            .font(VerbaFont.caption(size: 11))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    }
                    AmberProgressBar(
                        progress: max(0, min(1, progress)),
                        tint: VerbaTheme.ctaTop,
                        height: 8,
                        showsCap: true
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cozyBlockCard()
    }

    // MARK: - Stat row (3-up)

    private var statRow: some View {
        HStack(spacing: 10) {
            ClayStatTile.dayStreak(streakManager.currentStreak)
            ClayStatTile.studyDays(streakManager.totalStudyDays)
            ClayStatTile(
                value: streakManager.todayStudied ? "done" : "not yet",
                label: "today",
                icon: streakManager.todayStudied ? "checkmark.circle.fill" : "circle",
                tone: streakManager.todayStudied ? .mint : .cream
            )
        }
    }

    // MARK: - Weekly Activity Card

    private var weeklyActivityCard: some View {
        let bars = weeklyData()
        let maxCards  = bars.map(\.cards).max().map { max($0, 1) } ?? 1
        let totalWeek = bars.map(\.cards).reduce(0, +)
        let daysHit   = bars.filter { $0.cards > 0 }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEEKLY ACTIVITY")
                        .font(VerbaFont.syne(.bold, size: 10))
                        .tracking(1.4)
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    Text("\(totalWeek) cards · \(daysHit) of 7 days")
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                }
                Spacer()
            }

            Canvas { ctx, size in
                let count    = bars.count
                let spacing  = CGFloat(8)
                let barWidth = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
                let cap      = CGFloat(maxCards)

                for (i, bar) in bars.enumerated() {
                    let x      = CGFloat(i) * (barWidth + spacing)
                    let rawH   = size.height * 0.82 * CGFloat(bar.cards) / cap
                    let height = bar.cards > 0 ? max(8, rawH) : 4
                    let y      = size.height - height
                    let rect   = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path   = Path(roundedRect: rect, cornerRadius: 6)

                    let fillColor: Color = bar.isToday
                        ? VerbaTheme.ctaTop
                        : (bar.cards > 0 ? VerbaTheme.ctaTop.opacity(0.45) : VerbaTheme.oliveBorder.opacity(0.30))
                    ctx.fill(path, with: .color(fillColor))
                    ctx.stroke(path,
                               with: .color(VerbaTheme.oliveBorder.opacity(0.6)),
                               lineWidth: 1)
                }
            }
            .frame(height: 84)
            .accessibilityLabel(weeklyAccessibilityLabel(totalCards: totalWeek,
                                                         daysHit: daysHit,
                                                         bars: bars))
            .accessibilityElement(children: .ignore)

            HStack(spacing: 0) {
                ForEach(bars, id: \.dayLabel) { bar in
                    Text(bar.isToday ? "Now" : bar.dayLabel)
                        .font(VerbaFont.syne(bar.isToday ? .bold : .medium, size: 10))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(bar.isToday ? VerbaTheme.cozyForest : VerbaTheme.cozyOliveSubtext)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cozyBlockCard()
    }

    // MARK: - Deck Report Card

    private var deckReportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DECK REPORT")
                .font(VerbaFont.syne(.bold, size: 10))
                .tracking(1.4)
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                ForEach(activeDocuments) { doc in
                    deckRow(doc: doc)
                    if doc.id != activeDocuments.last?.id {
                        Divider()
                            .background(VerbaTheme.oliveBorder.opacity(0.30))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cozyBlockCard()
    }

    private func deckRow(doc: Document) -> some View {
        let items      = doc.studyItems
        let dueCount   = items.filter { $0.nextReviewAt <= Date() }.count
        let readiness  = ReadinessCalculator.quickScore(for: items, examDate: doc.examDate)
        let readColor: Color = readiness >= 80 ? VerbaTheme.ctaTop
            : readiness >= 50 ? VerbaTheme.orange
            : VerbaTheme.danger

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(doc.title)
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(1)
                Spacer()

                if let exam = doc.examDate {
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: exam).day ?? 0
                    if days >= 0 {
                        Text("\(days)d")
                            .font(VerbaFont.syne(.bold, size: 10))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(days <= 3 ? VerbaTheme.yellow.opacity(0.55) : VerbaTheme.glossCream))
                            .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.2))
                    }
                }

                if dueCount > 0 {
                    Text("\(dueCount) due")
                        .font(VerbaFont.syne(.bold, size: 10))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(VerbaTheme.glossCream))
                        .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.2))
                } else {
                    Text("caught up")
                        .font(VerbaFont.syne(.medium, size: 10))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }
            }

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(VerbaTheme.oliveBorder.opacity(0.30))
                            .frame(height: 8)
                        Capsule()
                            .fill(VerbaTheme.cozyLime)
                            .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.2))
                            .frame(width: geo.size.width * CGFloat(readiness) / 100.0, height: 8)
                            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.20),
                                    radius: 0, x: 0, y: 2)
                    }
                }
                .frame(height: 8)

                Text("\(readiness)%")
                    .font(VerbaFont.caption(size: 11))
                    .foregroundStyle(readColor)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Settings Block (toggle rows)

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionEyebrow("STUDY & NOTIFICATIONS")
            settingRow {
                HStack {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .frame(width: 28)
                    Text("daily goal")
                        .font(VerbaFont.syne(.semibold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Spacer()
                    Stepper(value: $dailyGoal, in: 5...100, step: 5) {
                        HStack(spacing: 4) {
                            Text("\(dailyGoal)")
                                .font(VerbaFont.syne(.bold, size: 16))
                                .foregroundStyle(VerbaTheme.cozyForest)
                                .monospacedDigit()
                            Text("cards")
                                .font(VerbaFont.syne(.medium, size: 12))
                                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Daily goal, \(dailyGoal) cards per day")
                    .accessibilityHint("Adjust to set how many flashcards you want to review each day. Stepper moves in steps of 5, between 5 and 100.")
                    .onChange(of: dailyGoal) { _, _ in
                        // Re-schedule reminders with the new goal so copy
                        // references the freshly-set target.
                        if smartReminders {
                            let now = Date()
                            let active = documents.filter { !$0.isArchived }
                            let due = active.flatMap(\.studyItems).filter { $0.nextReviewAt <= now }.count
                            let slipping = active.flatMap(\.studyItems).filter { $0.mastery < 50 && $0.nextReviewAt > now }.count
                            StudyReminderService.shared.scheduleAll(
                                dueCount: due,
                                slippingCount: slipping,
                                streakDays: streakManager.currentStreak,
                                todayStudied: streakManager.todayStudied,
                                dailyGoal: dailyGoal
                            )
                        }
                    }
                }
            }
            Divider().background(VerbaTheme.oliveBorder.opacity(0.30))
            settingRow {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .frame(width: 28)
                    Text("smart reminders")
                        .font(VerbaFont.syne(.semibold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Spacer()
                    Toggle("", isOn: $smartReminders).tint(VerbaTheme.ctaTop)
                        .accessibilityLabel("Smart study reminders")
                        .accessibilityHint("Sends a daily notification when you have cards due or your streak is at risk.")
                        .onChange(of: smartReminders) { _, newValue in
                            if newValue {
                                let now = Date()
                                let active = documents.filter { !$0.isArchived }
                                let due = active.flatMap(\.studyItems).filter { $0.nextReviewAt <= now }.count
                                let slipping = active.flatMap(\.studyItems).filter { $0.mastery < 50 && $0.nextReviewAt > now }.count
                                StudyReminderService.shared.scheduleAll(
                                    dueCount: due,
                                    slippingCount: slipping,
                                    streakDays: streakManager.currentStreak,
                                    todayStudied: streakManager.todayStudied,
                                    dailyGoal: dailyGoal
                                )
                            }
                        }
                }
            }
            Divider().background(VerbaTheme.oliveBorder.opacity(0.30))
            settingRow {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .frame(width: 28)
                    Text("AI cards")
                        .font(VerbaFont.syne(.semibold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Spacer()
                    Text("included")
                        .font(VerbaFont.syne(.bold, size: 12))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(VerbaTheme.glossCream))
                        .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.2))
                }
            }
            Divider().background(VerbaTheme.oliveBorder.opacity(0.30))
            settingRow {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .frame(width: 28)
                    Text("version")
                        .font(VerbaFont.syne(.semibold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Spacer()
                    Text(appVersion)
                        .font(VerbaFont.syne(.medium, size: 13))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .inset(by: 2)
                .stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 1.2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.20),
                radius: 0, x: 0, y: 5)
    }

    // MARK: - Account actions (sign-out + delete)

    private var accountActions: some View {
        VStack(spacing: 12) {
            // Section eyebrow — surfaces the W3.2 ACCOUNT ordering.
            sectionEyebrow("ACCOUNT")
            Button {
                Task { await AuthService.shared.signOut() }
            } label: {
                Text("sign out")
                    .font(VerbaFont.syne(.bold, size: 15))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                            .fill(VerbaTheme.glossCream)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                            .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                    )
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.20),
                            radius: 0, x: 0, y: 4)
            }
            .accessibilityLabel("Sign out of VerbaDoc account")
            .accessibilityHint("Returns to the sign-in screen. Your saved decks stay on this device.")

            VStack(spacing: 8) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        if isDeletingAccount { ProgressView().tint(VerbaTheme.cozyForest) }
                        Text(isDeletingAccount ? "deleting…" : "delete account")
                            .font(VerbaFont.syne(.semibold, size: 13))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.5)
                    )
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                            radius: 0, x: 0, y: 3)
                }
                .disabled(isDeletingAccount)
                    .accessibilityLabel(isDeletingAccount ? "Deleting account, please wait" : "Permanently delete VerbaDoc account")
                    .accessibilityHint("Removes your account and all your decks. This cannot be undone.")

                if let err = deleteError {
                    Text(err)
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Account deletion error: \(err)")
                }
            }
        }
    }

    // MARK: - Legal row

    private var legalRow: some View {
        HStack(spacing: 14) {
            Link("privacy policy", destination: URL(string: "https://verbadoc.app/privacy")!)
            Text("·").foregroundStyle(VerbaTheme.cozyOliveSubtext.opacity(0.4))
            Link("terms of service", destination: URL(string: "https://verbadoc.app/terms")!)
        }
        .font(VerbaFont.syne(.medium, size: 12))
        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        .padding(.top, 8)
    }

    // MARK: - Data

    private func weeklyData() -> [(dayLabel: String, cards: Int, isToday: Bool)] {
        let cal      = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let sessions = SessionTracker.shared.recentSessions
        let fmt      = DateFormatter()
        fmt.dateFormat = "EEE"

        return (0..<7).reversed().map { daysAgo in
            let day     = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayEnd  = cal.date(byAdding: .day, value: 1, to: day)!
            let cards   = sessions.filter { $0.date >= day && $0.date < dayEnd }.reduce(0) { $0 + $1.cardsReviewed }
            let label   = fmt.string(from: day)
            return (dayLabel: label, cards: cards, isToday: daysAgo == 0)
        }
    }

    // MARK: - Helpers

    private func nextRank() -> Rank? {
        let all = Rank.allCases
        guard let idx = all.firstIndex(of: xpManager.currentRank), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(VerbaTheme.cozyForest)
            Text(value)
                .font(VerbaFont.title(size: 20, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(VerbaFont.syne(.semibold, size: 10))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.20),
                radius: 0, x: 0, y: 4)
    }

    private func settingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(.horizontal, 18).padding(.vertical, 14)
    }

    /// Small uppercase olive-tinted label that communicates the W3.2
    /// section ordering (Account / Study / Notifications / Subscription /
    /// About / Legal). Renders inside the card chassis so the cohesive
    /// cozy-green look is preserved.
    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(VerbaFont.syne(.bold, size: 10))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    /// VoiceOver-friendly readout of the weekly activity chart.
    /// VoiceOver cannot read `.canvas` so we concatenate totals + per-day
    /// counts into one descriptive sentence.
    private func weeklyAccessibilityLabel(
        totalCards: Int,
        daysHit: Int,
        bars: [(dayLabel: String, cards: Int, isToday: Bool)]
    ) -> String {
        let daily = bars.map { bar in
            "\(bar.dayLabel): \(bar.cards) card\(bar.cards == 1 ? "" : "s")\(bar.isToday ? " (today)" : "")"
        }.joined(separator: ", ")
        return "Weekly activity: \(totalCards) cards across \(daysHit) of 7 days. \(daily)."
    }

    /// SF Symbol mapped to each rank — keeps the rank bubble as a
    /// chunky mint chip without depending on Rank's case labels
    /// (which would force the helper to track every renumber in
    /// XPManager). Indexes into `Rank.allCases` so the helper
    /// compiles regardless of case naming.
    private func rankIconName(for rank: Rank) -> String {
        guard let idx = Rank.allCases.firstIndex(of: rank) else { return "star.fill" }
        let total = max(Rank.allCases.count - 1, 1)
        let tier = Double(idx) / Double(total)
        switch tier {
        case ..<0.20:   return "leaf.fill"
        case ..<0.40:   return "book.fill"
        case ..<0.60:   return "graduationcap.fill"
        case ..<0.80:   return "sparkles"
        default:        return "crown.fill"
        }
    }
}
