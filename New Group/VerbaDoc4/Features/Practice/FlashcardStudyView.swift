import SwiftUI
import SwiftData
import StoreKit

// MARK: - DrillScope
//
// Filters the study queue before the session builds.
// .all   — full deck, SRS-ordered (existing behavior)
// .weak  — mastery < 50 only
// .due   — overdue cards only (nextReviewAt <= now)
// .topic — a specific topic cluster

enum DrillScope: Equatable {
    case all
    case weak
    case due
    case topic(String)

    var label: String {
        switch self {
        case .all:        return "all cards"
        case .weak:       return "weak spots"
        case .due:        return "due now"
        case .topic(let t): return t
        }
    }
}

// MARK: - FlashcardStudyView
//
// Tactile, warm, immersive. The card is everything.
// Syne for card text. Instrument Serif for emotional moments.
// Spring animations on every interaction.

struct FlashcardStudyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager

    let document: Document
    var scope: DrillScope = .all   // injected by caller — default preserves existing behavior

    // Queue state is owned by StudyQueueManager — single source of truth.
    @StateObject private var queueManager = StudyQueueManager()

    @State private var isFlipped        = false
    @State private var dragOffset: CGSize = .zero
    @State private var correctCount     = 0
    @State private var answeredCount    = 0
    @State private var showTutor        = false
    @State private var cardAppeared     = false
    /// The question text of the card missed most this session (consecutiveMisses ≥ 2).
    @State private var persistentlyMissedQuestion: String?
    // Adaptive session intelligence
    @State private var consecutiveWrong  = 0   // triggers easy-card injection at 3
    @State private var consecutiveRight  = 0   // focus streak
    @State private var peakStreak        = 0   // best streak this session
    @State private var conceptsRecovered = 0   // slipping cards answered correctly
    @State private var sessionStartMastery = 0 // average mastery when session began
    @State private var easyCardInjected  = false // don't spam injections
    @State private var forgettingMomentText: String? = nil
    @State private var forgettingFiredCount: Int = 0      // max 3 per session
    @State private var forgettingShownIDs: Set<String> = [] // one comment per card per session

    private let swipeThreshold: CGFloat = 80

    private var currentCard: StudyItem? { queueManager.currentCard }
    private var progress: Double        { queueManager.progress }

    private var accuracy: Double {
        answeredCount > 0 ? Double(correctCount) / Double(answeredCount) : 0
    }

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            if queueManager.queue.isEmpty && !queueManager.sessionComplete {
                emptyScopeView
                    .transition(.opacity)
            } else if queueManager.sessionComplete {
                sessionCompleteView
                    .transition(.opacity)
            } else if let card = currentCard {
                studyView(card: card)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(queueManager.currentIndex)
            }
        }
        .animation(.verba, value: queueManager.currentIndex)
        .animation(.verba, value: queueManager.sessionComplete)
        .overlay(alignment: .top) { topBar }
        .onAppear(perform: buildQueue)
        .sheet(isPresented: $showTutor) {
            if let card = currentCard { TutorView(item: card) }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                HapticManager.selection()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(VerbaTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(VerbaTheme.card)
                    .clipShape(Circle())
                    .shadow(color: VerbaTheme.shadow(0.06), radius: 8, x: 0, y: 2)
            }

            // Progress track — ink, not green. One accent color per screen.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(VerbaTheme.ink.opacity(0.08))
                        .frame(height: 2)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(VerbaTheme.ink.opacity(0.35))
                        .frame(width: progress * geo.size.width, height: 2)
                        .animation(.verba, value: progress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 16)

            // Focus streak badge — only appears when earned (≥ 3 correct in a row)
            if consecutiveRight >= 3 {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(consecutiveRight)")
                        .font(VerbaFont.syne(.bold, size: 12))
                }
                .foregroundStyle(VerbaTheme.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(VerbaTheme.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .animation(.verbaBounce, value: consecutiveRight)
            } else {
                VStack(spacing: 1) {
                    Text("\(queueManager.currentIndex + 1)/\(queueManager.queue.count)")
                        .font(VerbaFont.syne(.medium, size: 13))
                        .foregroundStyle(VerbaTheme.muted)
                    if scope != .all {
                        Text(scope.label)
                            .font(VerbaFont.syne(.regular, size: 10))
                            .foregroundStyle(VerbaTheme.green.opacity(0.7))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Study View

    private func studyView(card: StudyItem) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80) // clear top bar

            flashCard(card: card)
                .padding(.horizontal, 20)

            // Explain this — appears after flip
            if isFlipped {
                Button {
                    showTutor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text("explain this")
                            .font(VerbaFont.syne(.regular, size: 13))
                    }
                    .foregroundStyle(VerbaTheme.green)
                    .padding(.top, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Spacer()

            // Forgetting moment — shown for ~300ms after a wrong answer, before card advances.
            if let msg = forgettingMomentText {
                Text(msg)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.danger.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            answerRow(card: card)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
        }
        .animation(.verba, value: isFlipped)
        .animation(.easeInOut(duration: 0.20), value: forgettingMomentText)
    }

    // MARK: - Flash Card

    private func flashCard(card: StudyItem) -> some View {
        ZStack {
            // Swipe tint overlay
            let tintAmt = min(abs(dragOffset.width) / swipeThreshold, 1.0)
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .fill(dragOffset.width > 0
                      ? VerbaTheme.green.opacity(tintAmt * 0.08)
                      : VerbaTheme.danger.opacity(tintAmt * 0.08))

            VStack(alignment: .leading, spacing: 0) {
                // Label row
                HStack {
                    Text(isFlipped ? "answer" : "question")
                        .font(VerbaFont.syne(.medium, size: 11))
                        .foregroundStyle(isFlipped ? VerbaTheme.green : VerbaTheme.muted)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    swipeBadge

                    // Mastery dot
                    Circle()
                        .fill(masteryDotColor(card.mastery))
                        .frame(width: 7, height: 7)
                }
                .padding(.bottom, 22)

                // Card content
                ScrollView(showsIndicators: false) {
                    Text(isFlipped ? card.answer : card.question)
                        .font(VerbaFont.syne(.regular, size: 19))
                        .foregroundStyle(VerbaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(5)
                        .animation(.none, value: isFlipped)
                }

                Spacer(minLength: 20)

                if !isFlipped {
                    HStack {
                        Spacer()
                        Text("tap to flip")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.muted.opacity(0.6))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 280)
        }
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r20, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
        .shadow(color: VerbaTheme.shadow(0.06), radius: 12, x: 0, y: 3)
        // Subtle entrance — 0.98 not 0.94. Barely perceptible, not dramatic.
        .scaleEffect(cardAppeared ? 1 : 0.98)
        .opacity(cardAppeared ? 1 : 0)
        // Swipe physics — gentler rotation
        .rotationEffect(.degrees(Double(dragOffset.width) / 36))
        .offset(x: dragOffset.width, y: dragOffset.height * 0.08)
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { val in
                    guard !queueManager.isAdvancing else { return }
                    dragOffset = val.translation
                }
                .onEnded { val in
                    guard !queueManager.isAdvancing else { return }
                    handleSwipe(val.translation.width, card: card)
                }
        )
        .onTapGesture {
            guard !queueManager.isAdvancing else { return }
            HapticManager.selection()
            withAnimation(.easeInOut(duration: 0.18)) {
                isFlipped.toggle()
            }
        }
        .onChange(of: queueManager.currentIndex) { _, _ in
            cardAppeared = false
            withAnimation(.easeOut(duration: 0.20)) {
                cardAppeared = true
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                cardAppeared = true
            }
        }
    }

    @ViewBuilder
    private var swipeBadge: some View {
        if dragOffset.width > swipeThreshold {
            Text("got it")
                .font(VerbaFont.syne(.semibold, size: 12))
                .foregroundStyle(VerbaTheme.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(VerbaTheme.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                .transition(.scale.combined(with: .opacity))
        } else if dragOffset.width < -swipeThreshold {
            Text("missed")
                .font(VerbaFont.syne(.semibold, size: 12))
                .foregroundStyle(VerbaTheme.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(VerbaTheme.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func masteryDotColor(_ m: Int) -> Color {
        switch m {
        case 75...: return VerbaTheme.green
        case 40..<75: return VerbaTheme.orange
        default: return VerbaTheme.danger
        }
    }

    // MARK: - Answer Row

    private func answerRow(card: StudyItem) -> some View {
        HStack(spacing: 12) {
            // Missed
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
            .buttonStyle(VerbaButtonStyle(
                filled: false,
                backgroundColor: VerbaTheme.danger
            ))
            .disabled(queueManager.isAdvancing)

            // Got it / Reveal
            if isFlipped {
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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isFlipped = true
                    }
                } label: {
                    Text("reveal answer")
                        .font(VerbaFont.syne(.medium, size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VerbaButtonStyle())
                .disabled(queueManager.isAdvancing)
            }
        }
    }

    // MARK: - Empty Scope View
    // Shown when a scoped drill has zero qualifying cards.

    private var emptyScopeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                VerbaMascot(mood: .happy, size: 80)
                VStack(spacing: 8) {
                    Text(emptyScopeHeadline)
                        .font(VerbaFont.serif(size: 24))
                        .foregroundStyle(VerbaTheme.ink)
                        .multilineTextAlignment(.center)
                    Text(emptyScopeSubline)
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            Spacer()
            Button("done") { dismiss() }
                .outlineButtonStyle(color: VerbaTheme.muted)
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
        }
        .verbaBackground()
    }

    private var emptyScopeHeadline: String {
        switch scope {
        case .due:   return "you're on track."
        case .weak:  return "nothing weak here."
        case .topic: return "nothing to drill."
        case .all:   return "no cards yet."
        }
    }

    private var emptyScopeSubline: String {
        switch scope {
        case .due:   return "no cards are due for review right now. come back later or drill the full deck."
        case .weak:  return "all cards in this deck are above 50% mastery. solid work."
        case .topic(let t): return "no cards found for \"\(t)\". the topic may be empty."
        case .all:   return "this deck has no cards. generate some from the document view."
        }
    }

    // MARK: - Session Complete

    private var masteryGained: Int {
        let items = document.studyItems
        guard !items.isEmpty else { return 0 }
        let current = items.reduce(0) { $0 + $1.mastery } / items.count
        return max(0, current - sessionStartMastery)
    }

    private var sessionCompleteView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Mascot mood is data-driven
                VerbaMascot(
                    mood: accuracy >= 0.85 ? .lockedIn : accuracy >= 0.6 ? .cheering : .thinking,
                    size: 90
                )

                VStack(spacing: 8) {
                    Text(completionHeadline)
                        .font(VerbaFont.serif(size: 28))
                        .foregroundStyle(VerbaTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(completionSubline)
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(VerbaTheme.muted)
                        .multilineTextAlignment(.center)
                }

                // Stats strip
                statsStrip
                    .padding(.horizontal, 16)

                // Stuck concept callout — only shows when genuinely earned
                if let stuck = persistentlyMissedQuestion {
                    stuckConceptCallout(stuck)
                        .padding(.horizontal, 16)
                }

                // Next review hint — tells user exactly when to come back
                if !nextReviewHint.isEmpty {
                    Text(nextReviewHint)
                        .font(VerbaFont.syne(.regular, size: 13))
                        .foregroundStyle(VerbaTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button("study again") { restartSession() }
                    .primaryButtonStyle()

                Button("done") { dismiss() }
                    .outlineButtonStyle(color: VerbaTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .verbaBackground()
        .onAppear { computeNextReviewHint() }
    }

    // MARK: - Next Review Hint

    @State private var nextReviewHint: String = ""

    private func computeNextReviewHint() {
        let items = document.studyItems
        guard !items.isEmpty else { return }
        let now = Date()
        let upcoming = items
            .filter { $0.nextReviewAt > now }
            .map(\.nextReviewAt)
            .sorted()
        guard let nearest = upcoming.first else {
            nextReviewHint = "come back tomorrow to keep building."
            return
        }
        let interval = nearest.timeIntervalSince(now)
        let hours = Int(interval / 3600)
        if hours < 1 {
            nextReviewHint = "next review in under an hour."
        } else if hours < 24 {
            nextReviewHint = "next review in \(hours)h · come back then."
        } else {
            let days = hours / 24
            nextReviewHint = days == 1
                ? "next review tomorrow · you're on track."
                : "next review in \(days) days · you're ahead."
        }
    }

    private func stuckConceptCallout(_ question: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VerbaTheme.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("this one keeps coming back")
                    .font(VerbaFont.syne(.semibold, size: 12))
                    .foregroundStyle(VerbaTheme.orange)
                Text(question)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerbaTheme.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.orange.opacity(0.20), lineWidth: 1)
        )
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell("\(Int(accuracy * 100))%", label: "accuracy", color: accuracyColor)
            warmDivider
            statCell("\(answeredCount)", label: "reviewed", color: VerbaTheme.muted)
            warmDivider
            if masteryGained > 0 {
                statCell("+\(masteryGained)%", label: "mastery", color: VerbaTheme.green)
            } else {
                statCell("\(correctCount)", label: "correct", color: VerbaTheme.green)
            }
        }
        .padding(.vertical, 18)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    private func statCell(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VerbaFont.syne(.bold, size: 22))
                .foregroundStyle(color)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var warmDivider: some View {
        Rectangle()
            .fill(VerbaTheme.border)
            .frame(width: 1, height: 36)
    }

    private var completionHeadline: String {
        if conceptsRecovered > 0 && accuracy >= 0.75 { return "memory recovered." }
        if accuracy >= 0.90 { return "locked in." }
        if accuracy >= 0.75 { return "solid session." }
        if accuracy >= 0.50 { return "getting there." }
        return "keep grinding."
    }

    private var completionSubline: String {
        // Priority: recovery > streak > accuracy
        if conceptsRecovered > 0 {
            return "you recovered \(conceptsRecovered) slipping concept\(conceptsRecovered == 1 ? "" : "s")."
        }
        if peakStreak >= 5 {
            return "peak focus: \(peakStreak) in a row. \(correctCount) of \(answeredCount) right."
        }
        if masteryGained > 0 {
            return "mastery up \(masteryGained)%. \(correctCount) of \(answeredCount) right."
        }
        if accuracy >= 0.90 { return "\(correctCount) of \(answeredCount) right. that's elite." }
        if accuracy >= 0.75 { return "\(correctCount) of \(answeredCount) right. almost there." }
        if accuracy >= 0.50 { return "\(correctCount) of \(answeredCount). a few more reps." }
        return "\(correctCount) of \(answeredCount). you're building the foundation."
    }

    private var accuracyColor: Color {
        if accuracy >= 0.75 { return VerbaTheme.green }
        if accuracy >= 0.50 { return VerbaTheme.orange }
        return VerbaTheme.danger
    }

    // MARK: - Core Logic

    private func handleSwipe(_ width: CGFloat, card: StudyItem) {
        if width > swipeThreshold {
            processAnswer(correct: true, card: card)
        } else if width < -swipeThreshold {
            processAnswer(correct: false, card: card)
        } else {
            withAnimation(.verba) { dragOffset = .zero }
        }
    }

    private func processAnswer(correct: Bool, card: StudyItem) {
        guard !queueManager.isAdvancing else { return }
        queueManager.beginAdvance()

        // Track recoveries BEFORE mastery update (card was slipping, now answered right)
        if correct && card.consecutiveMisses >= 1 { conceptsRecovered += 1 }

        // Adaptive session counters
        if correct {
            HapticManager.success()
            correctCount     += 1
            consecutiveRight += 1
            consecutiveWrong  = 0
            peakStreak        = max(peakStreak, consecutiveRight)
            forgettingMomentText = nil
        } else {
            HapticManager.impact()
            consecutiveWrong += 1
            consecutiveRight  = 0
            // All queue mutations go through StudyQueueManager — never touch queue directly.
            queueManager.requeueMissed(card)
            if consecutiveWrong == 3 && !easyCardInjected {
                queueManager.injectEasyWin(from: document.studyItems, scope: scope)
                easyCardInjected = true
            }
            // Interpret the wrong answer as a memory event. Pure read — mutation below.
            let ctx = ForgetEventContext(
                consecutiveWrong:    consecutiveWrong,
                answeredCount:       answeredCount,
                sessionAccuracy:     accuracy,
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
        answeredCount += 1
        updateMastery(card: card, correct: correct)
        xpManager.award(.reviewCard)

        withAnimation(.easeOut(duration: 0.16)) { dragOffset = .zero }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            forgettingMomentText = nil
            queueManager.commitAdvance()
            isFlipped = false
            if queueManager.sessionComplete { recordSession() }
        }
    }

    // MARK: - Memory Event Resolution

    // Session context at the moment of a wrong answer.
    // Pure value type — no SwiftUI dependencies, no state mutation.
    private struct ForgetEventContext {
        let consecutiveWrong: Int
        let answeredCount: Int
        let sessionAccuracy: Double
        let firedCount: Int
        let alreadyShownForCard: Bool
    }

    // Candidate signals ranked by informational specificity.
    // Specificity = how precisely the signal names the cause of the memory failure.
    // Higher rawValue = higher priority. Only one is emitted per event.
    private enum ForgetSignal: Int, Comparable {
        case surpriseSlip    = 1  // named prior success, cause unknown
        case gapInduced      = 2  // names time gap as cause
        case decayConfirmed  = 3  // names SRS-predicted decay + exact days

        static func < (lhs: ForgetSignal, rhs: ForgetSignal) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // Resolves a wrong answer to exactly one memory failure interpretation, or nil.
    // Pure function — no side effects. Caller handles all state mutation.
    //
    // Architecture: evaluate ALL candidate signals independently, then select the
    // single highest-priority match. This makes priority explicit and auditable —
    // it cannot be changed accidentally by reordering code.
    //
    // Called BEFORE SRSScheduler mutates the card: all fields reflect the memory
    // state at the moment of failure, not the post-penalty state.
    private func resolveForgetEvent(card: StudyItem, context: ForgetEventContext) -> String? {
        // Session suppression — process constraints that override all signals.
        // These are evaluated once, up front, before any memory analysis.
        guard context.firedCount < 2 else { return nil }
        guard !context.alreadyShownForCard else { return nil }
        guard context.consecutiveWrong < 2 else { return nil }
        if context.answeredCount >= 5 && context.sessionAccuracy < 0.40 { return nil }

        let daysSince = card.lastReviewedAt
            .map { Date().timeIntervalSince($0) / 86400 } ?? 0.0

        // Evidence floor: was there real prior success to lose?
        // These two conditions together define "had a retrievable memory trace."
        guard card.reviewCount >= 3 && card.mastery >= 25 else { return nil }

        // Failure rate floor: the card must have been working before it started failing.
        // If consecutive misses exceed 1/3 of all reviews, the card was never consolidated.
        guard card.consecutiveMisses <= max(1, card.reviewCount / 3) else { return nil }

        // Evaluate all candidate signals independently.
        // Signals do not short-circuit each other — all are checked.
        var candidates: [ForgetSignal] = []

        let decayRatio = card.stabilityDays > 0 ? daysSince / card.stabilityDays : 0.0

        // Decay-confirmed: SRS model predicted imminent forgetting, and it happened.
        // Requires both ratio threshold (model signal) and absolute minimum (non-trivial gap).
        if decayRatio >= 0.75 && daysSince >= 2 {
            candidates.append(.decayConfirmed)
        }

        // Gap-induced: a meaningful time gap disrupted consolidation.
        // Does NOT require SRS prediction — applies when gap is real but stability was high.
        // Requires mastery floor to confirm there was something to lose.
        if daysSince >= 3 && card.mastery >= 35 {
            candidates.append(.gapInduced)
        }

        // Surprise slip: well-known card, no prior consecutive misses, short gap.
        // `daysSince < 3` is a hard upper bound: if time is the cause,
        // decayConfirmed or gapInduced will have fired instead. This signal
        // covers only the residual case where time is NOT the explanation.
        if card.mastery >= 55 && card.consecutiveMisses == 0 && daysSince < 3 {
            candidates.append(.surpriseSlip)
        }

        // Priority resolution: highest rawValue wins. Deterministic — no tie possible
        // because each signal occupies a distinct rank with no equal values.
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

    private func updateMastery(card: StudyItem, correct: Bool) {
        // Single call — StudyScheduler owns all card-state mutations.
        StudyScheduler.processAnswer(card: card, correct: correct)

        // persistentlyMissedQuestion is session-UI state, not card state — stays here.
        // consecutiveMisses was updated by processAnswer, so read the post-update value.
        if !correct && card.consecutiveMisses >= 2 && persistentlyMissedQuestion == nil {
            persistentlyMissedQuestion = card.question
        }
        try? modelContext.save()
    }

    private func buildQueue() {
        // StudyQueueManager owns all queue state — delegate build entirely.
        queueManager.build(from: document.studyItems, scope: scope)

        // Reset session-local state (not queue-related).
        let allItems = document.studyItems
        sessionStartMastery = allItems.isEmpty ? 0 : allItems.reduce(0) { $0 + $1.mastery } / allItems.count
        correctCount = 0; answeredCount = 0
        isFlipped = false; dragOffset = .zero
        cardAppeared = false
        persistentlyMissedQuestion = nil
        consecutiveWrong = 0; consecutiveRight = 0; peakStreak = 0
        conceptsRecovered = 0; easyCardInjected = false
        forgettingFiredCount = 0; forgettingShownIDs = []
    }

    private func restartSession() { buildQueue() }

    private func recordSession() {
        xpManager.award(.studySession)
        streakManager.recordStudySession()
        HapticManager.success()
        SessionTracker.shared.record(session: StudySession(
            date: Date(), cardsReviewed: answeredCount,
            correctCount: correctCount, duration: 0
        ))
        requestReviewIfEarned()
        generateReturnIntent()
    }

    /// Compute and persist a return prediction based on the cards just studied.
    /// Called once per completed session — pure addition, no SRS side effects.
    private func generateReturnIntent() {
        // Use the cards that were actually in this session's queue.
        let studiedItems = queueManager.queue
        guard !studiedItems.isEmpty else { return }
        if let intent = ReturnIntent.generate(for: document, studiedItems: studiedItems) {
            ReturnIntentStore.shared.save(intent)
        }
    }

    /// Asks for an App Store review after the user's 5th, 20th, and 50th sessions.
    /// SKStoreReviewRequest respects Apple's own rate limiting (max 3 prompts/year),
    /// so it's safe to call after every qualifying session — iOS decides whether to show it.
    private func requestReviewIfEarned() {
        let key = "sessions.completedCount"
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)
        let milestones: Set<Int> = [5, 20, 50]
        guard milestones.contains(count) else { return }
        // Must request from the active scene — use modern API (iOS 16+)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        AppStore.requestReview(in: scene)
    }
}
