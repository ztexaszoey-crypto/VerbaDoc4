import SwiftUI
import SwiftData

struct VerbaFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var tabRouter: TabRouter

    // Fix F-1: orphaned items (cardLayer == "orphan") are quarantined cards whose
    // parent document could not be found during a sync restore. They have malformed
    // or missing context and must never enter a study session. The predicate is
    // applied at the @Query level so SwiftData never loads them into this view.
    @Query(
        filter: #Predicate<StudyItem> { $0.cardLayer != "orphan" },
        sort: [
            SortDescriptor(\StudyItem.mastery),
            SortDescriptor(\StudyItem.nextReviewAt)
        ]
    )
    private var allItems: [StudyItem]

    @Query(filter: #Predicate<Document> { $0.examDate != nil && !$0.isArchived })
    private var documentsWithExams: [Document]

    @StateObject private var engine       = VerbaFlowEngine()
    @StateObject private var queueManager = StudyQueueManager()

    // MARK: - Cached lobby counts (Fix 6)
    //
    // Three O(N) Swift array filters on `allItems` would run on every SwiftUI
    // render cycle triggered by any @EnvironmentObject change (XP ticks, sync
    // state, streak updates). At 5k–20k cards these filters cause measurable
    // main-thread jitter.
    //
    // Solution: cache the counts in @State and recompute only when `allItems`
    // changes (SwiftData collection identity change = new items or deleted items).
    // Date() comparison for `dueCount` uses the start-of-minute so it doesn't
    // force a re-render every second — the lobby only needs approximate freshness.
    //
    // Note: @Query with #Predicate { $0.nextReviewAt <= Date() } is not viable
    // because SwiftData predicate macros don't support dynamic Date captures
    // (the predicate is compiled once and the date value is baked in).

    @State private var cachedDueCount:   Int = 0
    @State private var cachedWeakCount:  Int = 0
    @State private var cachedStuckCount: Int = 0

    // Fix 9: one-time first-drill CTA flag
    private static let firstDrillCTAKey = "verbadoc.firstDrillCTAShown"
    private var shouldShowFirstDrillCTA: Bool {
        !UserDefaults.standard.bool(forKey: Self.firstDrillCTAKey) && !allItems.isEmpty
    }

    @State private var sessionActive   = false
    @State private var isFlipped       = false
    @State private var dragOffset: CGSize = .zero
    @State private var cardAppeared    = false
    @State private var showOnboarding  = false
    @State private var forgettingMomentText: String? = nil
    @State private var forgettingFiredCount: Int = 0
    @State private var forgettingShownIDs: Set<String> = []

    private let swipeThreshold: CGFloat = 80

    // MARK: - Render state (no logic here)

    private var ui: FlowUIController {
        FlowUIController(
            energy:              engine.energy,
            mode:                engine.mode,
            isGate:              engine.currentCardIsGate,
            streakCount:         engine.streakCount,
            flowSpeedMultiplier: engine.flowSpeedMultiplier
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                Group {
                    if !sessionActive {
                        lobbyView
                            .transition(.opacity)
                    } else if queueManager.sessionComplete {
                        completeView
                            .transition(.opacity)
                    } else if let card = queueManager.currentCard {
                        sessionView(card: card)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .opacity
                            ))
                            .id(queueManager.currentIndex)
                    } else {
                        lobbyView
                    }
                }
                .animation(.verba, value: queueManager.currentIndex)
                .animation(.verba, value: sessionActive)
                .animation(.verba, value: queueManager.sessionComplete)

                if showOnboarding {
                    VerbaFlowOnboarding(isPresented: $showOnboarding)
                        .zIndex(100)
                }
            }
            .navigationTitle("drill")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            recomputeLobbyStats()
            // Auto-start when there are overdue or stuck cards — skip the lobby tap.
            // Returning users with urgent cards go straight to the first card.
            // First-time users (allItems empty) still see the lobby + CTA.
            let due   = allItems.filter { $0.nextReviewAt <= Date() }.count
            let stuck = allItems.filter { $0.consecutiveMisses >= 2 }.count
            if (due > 0 || stuck > 0) && !sessionActive {
                startSession()
            }
        }
        .onChange(of: allItems) { _, _ in recomputeLobbyStats() }
        .onDisappear { engine.endSession() }
        .onChange(of: queueManager.currentIndex) { _, _ in
            isFlipped = false; dragOffset = .zero
            cardAppeared = false
            withAnimation(.easeOut(duration: ui.cardTransitionDuration).delay(0.04)) {
                cardAppeared = true
            }
        }
        .onChange(of: queueManager.sessionComplete) { _, complete in
            if complete {
                xpManager.award(.studySession)
                // ── Quality bonuses (stackable with base award) ────────────────
                // flowSession and highAccuracyBonus are mutually exclusive —
                // flow mode implies high accuracy, so we only award the higher one.
                if engine.peakModeReached == .flow {
                    xpManager.award(.flowSession)
                } else if engine.accuracy >= 0.90 {
                    xpManager.award(.highAccuracyBonus)
                }
                // Long-streak bonus is independent — can stack with either above.
                if engine.peakStreak >= 7 {
                    xpManager.award(.longStreakBonus)
                }
                streakManager.recordStudySession()
                HapticManager.success()
                SessionTracker.shared.record(session: StudySession(
                    date: Date(), cardsReviewed: engine.sessionCards,
                    correctCount: engine.sessionCorrect, duration: 0
                ))
                // Reschedule smart reminders based on updated card state
                let due      = allItems.filter { $0.nextReviewAt <= Date() }.count
                let slipping = allItems.filter { $0.consecutiveMisses >= 2 }.count
                StudyReminderService.shared.scheduleAll(
                    dueCount:     due,
                    slippingCount: slipping,
                    streakDays:   streakManager.currentStreak,
                    todayStudied: true
                )
            }
        }
    }

    // MARK: - Lobby

    private var lobbyView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 20)

                // Fix 8: "all caught up" state — distinct from the normal lobby
                if !allItems.isEmpty && dueCount == 0 && stuckCount == 0 {
                    caughtUpState
                        .padding(.horizontal, 24)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lobbyHeadline)
                            .font(VerbaFont.serif(size: 28))
                            .foregroundStyle(VerbaTheme.ink)
                            .lineSpacing(2)
                        Text(lobbySubline)
                            .font(VerbaFont.syne(.regular, size: 14))
                            .foregroundStyle(VerbaTheme.muted)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 24)

                    if !allItems.isEmpty {
                        HStack(spacing: 12) {
                            statCard("\(dueCount)", label: "slipping",
                                     color: dueCount > 0 ? VerbaTheme.orange : VerbaTheme.muted)
                            statCard("\(weakCount)", label: "weak",
                                     color: weakCount > 0 ? VerbaTheme.danger : VerbaTheme.muted)
                            statCard("\(allItems.count)", label: "in vault",
                                     color: VerbaTheme.muted)
                        }
                        .padding(.horizontal, 20)

                        if stuckCount > 0 {
                            MascotSpeech(
                                text: "\(stuckCount) concept\(stuckCount == 1 ? "" : "s") keep\(stuckCount == 1 ? "s" : "") coming back. let's break the pattern.",
                                mood: .worried,
                                mascotSize: 48
                            )
                            .padding(.horizontal, 24)
                        } else if dueCount > 0 {
                            MascotSpeech(
                                text: "\(dueCount) concept\(dueCount == 1 ? "" : "s") slipping. one session locks them back in.",
                                mood: .happy,
                                mascotSize: 48
                            )
                            .padding(.horizontal, 24)
                        }
                    }
                }

                Spacer(minLength: 16)

                if allItems.isEmpty {
                    VStack(spacing: 20) {
                        VerbaMascot(mood: .sleeping, size: 72, animate: false)
                            .frame(maxWidth: .infinity)

                        Button {
                            tabRouter.selected = .upload
                        } label: {
                            Text("add your first set")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButtonStyle()
                    }
                    .padding(.horizontal, 24)
                } else if dueCount == 0 && stuckCount == 0 {
                    // All caught up — offer a bonus drill but don't demand one
                    Button {
                        startSession()
                    } label: {
                        Text("drill weak spots anyway")
                            .frame(maxWidth: .infinity)
                    }
                    .outlineButtonStyle(color: VerbaTheme.muted)
                    .padding(.horizontal, 24)
                } else {
                    // Fix 9: first-drill CTA — shown once after first generation
                    if shouldShowFirstDrillCTA {
                        firstDrillCTA
                            .padding(.horizontal, 24)
                    } else {
                        Button {
                            startSession()
                        } label: {
                            Text("start drilling")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButtonStyle()
                        .padding(.horizontal, 24)
                    }
                }

                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Start Session (shared helper)

    private func startSession() {
        engine.buildSession(from: allItems, queueManager: queueManager)
        // Guard: if buildWithWarmup produced zero cards (e.g. all cards are
        // maintenance/archived and none are due), stay in the lobby.
        // Without this, sessionActive = true with an empty queue leaves the user
        // in a stuck state with no visible "end" button.
        guard !queueManager.queue.isEmpty else { return }
        forgettingFiredCount = 0; forgettingShownIDs = []
        if !UserDefaults.standard.bool(forKey: "verbadoc.flowOnboardingComplete") {
            showOnboarding = true
        }
        withAnimation(.verba) { sessionActive = true }
        cardAppeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.22)) { cardAppeared = true }
        }
    }

    // MARK: - All Caught Up State (Fix 8)

    private var caughtUpState: some View {
        VStack(alignment: .leading, spacing: 20) {
            VerbaMascot(mood: .cheering, size: 72, animate: true)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("you're all caught up.")
                    .font(VerbaFont.serif(size: 28))
                    .foregroundStyle(VerbaTheme.ink)
                if streakManager.currentStreak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(VerbaTheme.orange)
                        Text("\(streakManager.currentStreak) day streak — keep it going.")
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    .font(VerbaFont.syne(.medium, size: 14))
                }
                Text(nextSessionText)
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineSpacing(2)
            }

            // Vault summary — compact, data-driven
            HStack(spacing: 12) {
                statCard("\(allItems.count)", label: "in vault", color: VerbaTheme.muted)
                statCard("\(weakCount)", label: "weak spots",
                         color: weakCount > 0 ? VerbaTheme.orange : VerbaTheme.muted)
            }
        }
    }

    private var nextSessionText: String {
        // Find earliest nextReviewAt across all items
        let next = allItems.compactMap { $0.nextReviewAt as Date? }.min()
        guard let next else { return "nothing due. add more material to keep growing." }
        let hours = Calendar.current.dateComponents([.hour], from: Date(), to: next).hour ?? 0
        if hours <= 0   { return "some cards are ready to review now." }
        if hours == 1   { return "next review in about an hour." }
        if hours < 24   { return "next review in \(hours) hours." }
        let days = hours / 24
        return "next review in \(days == 1 ? "1 day" : "\(days) days"). memory is consolidating."
    }

    // MARK: - First Drill CTA (Fix 9)

    private var firstDrillCTA: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("your deck is ready.")
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(VerbaTheme.ink)
                Text("VerbaFlow uses your answers to schedule reviews at the exact moment before you forget — weaker cards come back sooner, mastered ones later.")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(VerbaTheme.green.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(VerbaTheme.green.opacity(0.15), lineWidth: 1)
            )

            Button {
                UserDefaults.standard.set(true, forKey: Self.firstDrillCTAKey)
                startSession()
            } label: {
                Text("start your first drill")
                    .frame(maxWidth: .infinity)
            }
            .primaryButtonStyle()

            Button {
                UserDefaults.standard.set(true, forKey: Self.firstDrillCTAKey)
            } label: {
                Text("maybe later")
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    private func statCard(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VerbaFont.syne(.bold, size: 22))
                .foregroundStyle(color)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    // Lobby counts read from cache — O(1) in render, O(N) only on collection change.
    private var dueCount:   Int { cachedDueCount }
    private var weakCount:  Int { cachedWeakCount }
    private var stuckCount: Int { cachedStuckCount }

    private func recomputeLobbyStats() {
        let now = Date()
        var due = 0, weak = 0, stuck = 0
        for item in allItems {
            if item.nextReviewAt <= now  { due   += 1 }
            if item.mastery < 50         { weak  += 1 }
            if item.consecutiveMisses >= 2 { stuck += 1 }
        }
        cachedDueCount   = due
        cachedWeakCount  = weak
        cachedStuckCount = stuck
    }

    private var lobbyHeadline: String {
        if allItems.isEmpty { return "your drill pad\nis waiting." }
        if stuckCount > 0   { return "let's fix\nwhat's sticking." }
        if dueCount > 0     { return "concepts are\nslipping. drill now." }
        return "zero to mastery.\nlet's go."
    }

    private var lobbySubline: String {
        if allItems.isEmpty { return "upload your notes and we'll build your drill session." }
        if stuckCount > 0   { return "\(stuckCount) concept\(stuckCount == 1 ? "" : "s") you keep getting wrong. weak spots load first." }
        if dueCount > 0     { return "\(dueCount) concept\(dueCount == 1 ? "" : "s") due for review. weakest first." }
        return "everything's on track. weakest concepts load first."
    }

    // MARK: - Session View

    private func sessionView(card: StudyItem) -> some View {
        VStack(spacing: 0) {
            sessionHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

            Spacer()

            flowCard(card: card)
                .padding(.horizontal, 20)
                .scaleEffect(cardAppeared ? 1 : 0.98)
                .opacity(cardAppeared ? 1 : 0)

            Spacer()

            // Forgetting moment — briefly visible after a wrong answer before card advances.
            if let msg = forgettingMomentText {
                Text(msg)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.danger.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            answerButtons(card: card)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
        }
        .animation(.easeInOut(duration: 0.20), value: forgettingMomentText)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("end") {
                    // Fix F-3: cancel any in-flight advance task before leaving.
                    // Without this, a task created 120ms ago fires after sessionActive
                    // turns false and awards phantom XP + streak for the cancelled session.
                    engine.endSession()
                    withAnimation(.verba) { sessionActive = false }
                }
                .font(VerbaFont.syne(.regular, size: 15))
                .foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Mode label — text only, no pill
                Text(ui.modeLabel)
                    .font(VerbaFont.syne(.medium, size: 11))
                    .foregroundStyle(ui.modeColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .animation(.verba, value: engine.mode)

                // Energy bar — ink track, mode-colored fill
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(VerbaTheme.ink.opacity(0.08))
                            .frame(height: 2)
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(ui.modeColor)
                            .frame(
                                width: max(4, ui.energyFill * geo.size.width),
                                height: 2
                            )
                            .animation(.verba, value: engine.energy)
                    }
                }
                .frame(height: 2)

                // Streak badge (3+ consecutive correct)
                if let badge = ui.streakBadgeText {
                    Text(badge)
                        .font(VerbaFont.syne(.semibold, size: 10))
                        .foregroundStyle(VerbaTheme.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VerbaTheme.green.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r4, style: .continuous))
                        .transition(.scale.combined(with: .opacity))
                        .animation(.verbaBounce, value: engine.streakCount)
                }
            }

            HStack {
                // Gate indicator — shown when the current card is a checkpoint
                if ui.showGateIndicator {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ui.modeColor)
                        Text("checkpoint")
                            .font(VerbaFont.syne(.medium, size: 11))
                            .foregroundStyle(ui.modeColor)
                    }
                    .transition(.opacity.combined(with: .scale))
                    .animation(.verba, value: ui.showGateIndicator)
                } else {
                    Text(ui.modeSubtitle)
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.muted)
                }

                Spacer()

                Text("\(engine.sessionCards)/\(queueManager.queue.count)  ·  \(Int(engine.accuracy * 100))% right")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
                    .accessibilityLabel("\(engine.sessionCards) of \(queueManager.queue.count) cards. \(Int(engine.accuracy * 100)) percent correct.")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session progress: \(engine.sessionCards) of \(queueManager.queue.count) cards, \(Int(engine.accuracy * 100)) percent accuracy, \(Int(engine.energy)) energy, mode \(engine.mode.rawValue.lowercased())")
    }

    // MARK: - Flow Card

    private func flowCard(card: StudyItem) -> some View {
        ZStack {
            let tintAmt = min(abs(dragOffset.width) / swipeThreshold, 1.0)
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .fill(dragOffset.width > 0
                      ? VerbaTheme.green.opacity(tintAmt * 0.07)
                      : VerbaTheme.danger.opacity(tintAmt * 0.07))

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(isFlipped ? "answer" : "question")
                        .font(VerbaFont.syne(.medium, size: 11))
                        .foregroundStyle(isFlipped ? VerbaTheme.green : VerbaTheme.muted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    swipeDirectionBadge
                }
                .padding(.bottom, 22)

                ScrollView(showsIndicators: false) {
                    Text(isFlipped ? card.answer : card.question)
                        .font(VerbaFont.syne(.regular, size: 19))
                        .foregroundStyle(VerbaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(5)
                        .animation(.none, value: isFlipped)
                }

                Spacer(minLength: 16)

                if !isFlipped {
                    HStack {
                        Spacer()
                        Text("tap to flip")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.muted.opacity(0.55))
                    }
                }

                // Review and recovery both require reveal before marking correct
                if (engine.mode == .review || engine.mode == .recovery) && !isFlipped {
                    Text("reveal before marking correct")
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(ui.modeColor.opacity(0.80))
                        .padding(.top, 6)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 270)
        }
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .stroke(
                    // Gate card: colored border matches mode
                    ui.showGateIndicator ? ui.modeColor.opacity(0.30) : VerbaTheme.border,
                    lineWidth: 1
                )
        )
        .shadow(color: VerbaTheme.shadow(0.06), radius: 12, x: 0, y: 3)
        .rotationEffect(.degrees(Double(dragOffset.width) / 36))
        .offset(x: dragOffset.width, y: dragOffset.height * 0.10)
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { val in
                    guard !queueManager.isAdvancing else { return }
                    withAnimation(.verbaSnappy) { dragOffset = val.translation }
                }
                .onEnded { val in
                    guard !queueManager.isAdvancing else { return }
                    handleSwipe(val.translation.width, card: card)
                }
        )
        .onTapGesture {
            guard !queueManager.isAdvancing else { return }
            HapticManager.selection()
            withAnimation(.easeInOut(duration: 0.18)) { isFlipped.toggle() }
        }
        // MARK: - Accessibility
        // VoiceOver reads the card content, announces flip state, and
        // exposes custom actions so users can answer without swiping.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isFlipped
                ? "Answer: \(card.answer)"
                : "Question: \(card.question)"
        )
        .accessibilityHint(
            isFlipped
                ? "Swipe right to mark correct, swipe left to mark missed."
                : "Double-tap to flip card and see the answer."
        )
        .accessibilityAddTraits(isFlipped ? [] : .isButton)
        .accessibilityAction(named: "Flip card") {
            guard !queueManager.isAdvancing else { return }
            HapticManager.selection()
            withAnimation(.easeInOut(duration: 0.18)) { isFlipped.toggle() }
        }
        .accessibilityAction(named: "Mark correct") {
            guard isFlipped || (engine.mode != .review && engine.mode != .recovery) else { return }
            processAnswer(correct: true, card: card)
        }
        .accessibilityAction(named: "Mark missed") {
            processAnswer(correct: false, card: card)
        }
    }

    @ViewBuilder
    private var swipeDirectionBadge: some View {
        if dragOffset.width > swipeThreshold {
            Text("got it")
                .font(VerbaFont.syne(.semibold, size: 12))
                .foregroundStyle(VerbaTheme.green)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(VerbaTheme.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                .transition(.scale.combined(with: .opacity))
        } else if dragOffset.width < -swipeThreshold {
            Text("missed")
                .font(VerbaFont.syne(.semibold, size: 12))
                .foregroundStyle(VerbaTheme.danger)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(VerbaTheme.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Answer Buttons

    private func answerButtons(card: StudyItem) -> some View {
        HStack(spacing: 12) {
            Button {
                processAnswer(correct: false, card: card)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                    Text("missed")
                        .font(VerbaFont.syne(.medium, size: 14))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(VerbaButtonStyle(filled: false, backgroundColor: VerbaTheme.danger))
            .disabled(queueManager.isAdvancing)

            // Review + recovery: require flip before marking correct
            if isFlipped || (engine.mode != .review && engine.mode != .recovery) {
                Button {
                    processAnswer(correct: true, card: card)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                        Text("got it")
                            .font(VerbaFont.syne(.medium, size: 14))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(VerbaButtonStyle())
                .disabled(queueManager.isAdvancing)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isFlipped = true }
                } label: {
                    Text("reveal")
                        .font(VerbaFont.syne(.medium, size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VerbaButtonStyle())
                .disabled(queueManager.isAdvancing)
            }
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Mascot mood driven by session performance
                VerbaMascot(
                    mood: engine.peakModeReached == .flow ? .lockedIn :
                          engine.accuracy >= 0.7 ? .cheering : .happy,
                    size: 88
                )

                VStack(spacing: 8) {
                    Text(completionHeadline)
                        .font(VerbaFont.serif(size: 26))
                        .foregroundStyle(VerbaTheme.ink)
                    Text(completionSubline)
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(VerbaTheme.muted)
                        .multilineTextAlignment(.center)
                }

                // Session summary — data-driven only
                sessionSummaryGrid
                    .padding(.horizontal, 24)
            }

            Spacer()

            tomorrowSection

            VStack(spacing: 10) {
                Button("study again") {
                    engine.restart(from: allItems, queueManager: queueManager)
                    isFlipped = false; dragOffset = .zero
                }
                .primaryButtonStyle()

                Button("done") {
                    withAnimation(.verba) { sessionActive = false }
                }
                .outlineButtonStyle(color: VerbaTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
    }

    // MARK: - Nearest upcoming exam
    // Queries Document objects directly — avoids faulting StudyItem→Document
    // relationships (O(N items) → O(M documents with exam dates)).
    private var nearestExam: (title: String, daysLeft: Int)? {
        let now = Calendar.current.startOfDay(for: Date())
        return documentsWithExams
            .compactMap { doc -> (String, Int)? in
                guard let exam = doc.examDate else { return nil }
                let days = Calendar.current.dateComponents([.day], from: now, to: exam).day ?? Int.max
                guard days >= 0 else { return nil }
                return (doc.title, days)
            }
            .min(by: { $0.1 < $1.1 })
    }

    private var tomorrowSection: some View {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let dueCount = allItems.filter { $0.nextReviewAt <= tomorrow && $0.nextReviewAt > Date() }.count
        let slippingNow = allItems.filter { $0.nextReviewAt <= Date() }.count
        let estimatedMinutes = max(1, (dueCount + slippingNow) / 3) // ~20s per card
        let exam = nearestExam

        guard dueCount > 0 || slippingNow > 0 || exam != nil else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 0) {
                Divider().background(VerbaTheme.border)
                    .padding(.horizontal, 24)

                // Exam countdown — shown prominently when exam is within 14 days
                if let (title, days) = exam, days <= 14 {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(days <= 3 ? VerbaTheme.danger.opacity(0.10) : VerbaTheme.orange.opacity(0.10))
                                .frame(width: 36, height: 36)
                            Image(systemName: days == 0 ? "exclamationmark.circle.fill" : "alarm")
                                .font(.system(size: 16))
                                .foregroundStyle(days <= 3 ? VerbaTheme.danger : VerbaTheme.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(days == 0 ? "exam is today" : days == 1 ? "exam tomorrow" : "\(days) days until exam")
                                .font(VerbaFont.syne(.semibold, size: 14))
                                .foregroundStyle(days <= 3 ? VerbaTheme.danger : VerbaTheme.ink)
                            Text(title)
                                .font(VerbaFont.syne(.regular, size: 12))
                                .foregroundStyle(VerbaTheme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                    if dueCount > 0 || slippingNow > 0 {
                        Divider().background(VerbaTheme.border).padding(.horizontal, 24)
                    }
                }

                if dueCount > 0 || slippingNow > 0 {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("tomorrow")
                                .font(VerbaFont.syne(.semibold, size: 11))
                                .foregroundStyle(VerbaTheme.muted)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            if dueCount > 0 {
                                Text("\(dueCount) concept\(dueCount == 1 ? "" : "s") due · ~\(estimatedMinutes) min")
                                    .font(VerbaFont.syne(.regular, size: 14))
                                    .foregroundStyle(VerbaTheme.ink)
                            }
                            if slippingNow > 0 {
                                Text("\(slippingNow) already slipping")
                                    .font(VerbaFont.syne(.regular, size: 13))
                                    .foregroundStyle(VerbaTheme.orange)
                            }
                        }
                        Spacer()
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        )
    }

    // MARK: - Session Summary Grid

    private var sessionSummaryGrid: some View {
        let tracker = engine.masteryTracker
        let masteryGained = tracker?.masteryGained(for: allItems) ?? 0
        let weakHit = tracker?.weakTopicsHit.count ?? 0

        return VStack(spacing: 1) {
            // Row 1: accuracy | energy delta
            HStack(spacing: 0) {
                summaryCell(
                    "\(Int(engine.accuracy * 100))%",
                    label: "accuracy",
                    color: completionColor
                )
                summaryDivider
                summaryCell(
                    "\(Int(engine.sessionStartEnergy))→\(Int(engine.energy))",
                    label: "energy",
                    color: ui.modeColor
                )
            }

            Rectangle()
                .fill(VerbaTheme.border)
                .frame(height: 1)

            // Row 2: peak streak | weak topics hit
            HStack(spacing: 0) {
                summaryCell(
                    engine.peakStreak > 0 ? "\(engine.peakStreak)" : "—",
                    label: "peak streak",
                    color: engine.peakStreak >= 3 ? VerbaTheme.green : VerbaTheme.muted
                )
                summaryDivider
                summaryCell(
                    weakHit > 0 ? "\(weakHit)" : "none",
                    label: "weak hit",
                    color: weakHit > 0 ? VerbaTheme.orange : VerbaTheme.muted
                )
            }

            // Row 3: mastery gained (only when positive)
            if masteryGained > 0 {
                Rectangle()
                    .fill(VerbaTheme.border)
                    .frame(height: 1)

                summaryCell(
                    "+\(masteryGained)%",
                    label: "mastery gained",
                    color: VerbaTheme.green
                )
                .frame(maxWidth: .infinity)
            }
        }
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    private func summaryCell(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VerbaFont.syne(.bold, size: 20))
                .foregroundStyle(color)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(VerbaTheme.border)
            .frame(width: 1, height: 32)
    }

    private var completionHeadline: String {
        switch engine.peakModeReached {
        case .flow:
            return engine.accuracy >= 0.90 ? "locked in." : "you were in the zone."
        case .normal:
            return engine.accuracy >= 0.75 ? "memory stabilized." : "solid session."
        case .review:
            return engine.accuracy >= 0.5 ? "you're back on pace." : "keep grinding."
        case .recovery:
            return "recovery complete."
        }
    }

    private var completionSubline: String {
        let correct = engine.sessionCorrect
        let total   = engine.sessionCards
        let pct     = Int(engine.accuracy * 100)
        switch engine.peakModeReached {
        case .flow:
            return "\(correct) of \(total) right. you were locked in."
        case .normal:
            return pct >= 75
                ? "\(correct) of \(total) right. memory stabilizing."
                : "\(correct) of \(total) right. keep the reps coming."
        case .review:
            return correct > 0
                ? "\(correct) of \(total) right. every rep counts."
                : "tough session. the hard ones come back. stay with it."
        case .recovery:
            return "\(correct) of \(total) right. weak concepts reinforced."
        }
    }

    private var completionColor: Color {
        switch engine.peakModeReached {
        case .flow:     return VerbaTheme.green
        case .normal:   return VerbaTheme.yellow
        case .review:   return VerbaTheme.orange
        case .recovery: return VerbaTheme.danger
        }
    }

    // MARK: - Core Logic

    private func handleSwipe(_ width: CGFloat, card: StudyItem) {
        let requireReveal = engine.mode == .review || engine.mode == .recovery
        if width > swipeThreshold {
            if requireReveal && !isFlipped {
                HapticManager.selection()
                withAnimation(.verba) { dragOffset = .zero; isFlipped = true }
            } else {
                processAnswer(correct: true, card: card)
            }
        } else if width < -swipeThreshold {
            processAnswer(correct: false, card: card)
        } else {
            withAnimation(.verba) { dragOffset = .zero }
        }
    }

    private func processAnswer(correct: Bool, card: StudyItem) {
        if correct {
            HapticManager.success()
            forgettingMomentText = nil
        } else {
            HapticManager.impact()
            // VerbaFlow: streakCount guards against interrupting a correct-answer run.
            // A non-zero streakCount means the user was on a run before this miss —
            // the engine has already reset it, but we read it before processAnswer fires.
            let ctx = ForgetEventContext(
                consecutiveWrong:    engine.streakCount,
                answeredCount:       engine.sessionCards,
                sessionAccuracy:     engine.sessionCards > 0
                    ? Double(engine.sessionCorrect) / Double(engine.sessionCards) : 1.0,
                firedCount:          forgettingFiredCount,
                alreadyShownForCard: forgettingShownIDs.contains(card.id)
            )
            if let phrase = resolveForgetEvent(card: card, context: ctx) {
                forgettingMomentText = phrase
                forgettingFiredCount += 1
                forgettingShownIDs.insert(card.id)
            } else {
                forgettingMomentText = nil
            }
        }
        engine.processAnswer(correct: correct, card: card, queueManager: queueManager) {
            try? modelContext.save()
        }
        CloudSyncEngine.shared.enqueueStudyItemSync(id: card.id)
        xpManager.award(.reviewCard)
        withAnimation(.easeOut(duration: ui.cardTransitionDuration)) { dragOffset = .zero }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            forgettingMomentText = nil
        }
    }

    // MARK: - Memory Event Resolution

    private struct ForgetEventContext {
        let consecutiveWrong: Int   // engine.streakCount in VerbaFlow (correct-run guard)
        let answeredCount: Int
        let sessionAccuracy: Double
        let firedCount: Int
        let alreadyShownForCard: Bool
    }

    private enum ForgetSignal: Int, Comparable {
        case surpriseSlip   = 1
        case gapInduced     = 2
        case decayConfirmed = 3

        static func < (lhs: ForgetSignal, rhs: ForgetSignal) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private func resolveForgetEvent(card: StudyItem, context: ForgetEventContext) -> String? {
        guard context.firedCount < 2 else { return nil }
        guard !context.alreadyShownForCard else { return nil }
        guard context.consecutiveWrong < 2 else { return nil }
        if context.answeredCount >= 5 && context.sessionAccuracy < 0.40 { return nil }

        let daysSince = card.lastReviewedAt
            .map { Date().timeIntervalSince($0) / 86400 } ?? 0.0

        guard card.reviewCount >= 3 && card.mastery >= 25 else { return nil }
        guard card.consecutiveMisses <= max(1, card.reviewCount / 3) else { return nil }

        var candidates: [ForgetSignal] = []

        let decayRatio = card.stabilityDays > 0 ? daysSince / card.stabilityDays : 0.0
        if decayRatio >= 0.75 && daysSince >= 2              { candidates.append(.decayConfirmed) }
        if daysSince >= 3 && card.mastery >= 35               { candidates.append(.gapInduced) }
        if card.mastery >= 55 && card.consecutiveMisses == 0
            && daysSince < 3                                   { candidates.append(.surpriseSlip) }

        guard let winner = candidates.max() else { return nil }

        switch winner {
        case .decayConfirmed:
            let days = Int(daysSince)
            return "it faded over \(days) day\(days == 1 ? "" : "s")."
        case .gapInduced:
            return "the gap cost you this one."
        case .surpriseSlip:
            return "you knew this. it just slipped."
        }
    }
}
