import SwiftUI
import SwiftData

// MARK: - FlashcardStudyView
//
// The premium study surface — a calm, layered, motion-rich environment
// for review. Pure aesthetic / layout file: every business-logic
// func / State / EnvironmentObject / onAppear payload is preserved
// VERBATIM. UI is rebuilt around a multi-layer gradient background,
// a hero header with progress + XP + streak, and a 3D-flip card on
// floating depth.

struct FlashcardStudyView: View {
    let document: Document
    let scope: DrillScope

    // Explicit memberwise init with default. See DrillScope.swift header.
    init(document: Document, scope: DrillScope = .all) {
        self.document = document
        self.scope = scope
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager

    @StateObject private var queueManager = StudyQueueManager()

    // Study state
    @State private var showingAnswer   = false
    @State private var cardOffset      = CGSize.zero
    @State private var cardRotation    = 0.0
    @State private var swipeResult:    SwipeResult? = nil
    @State private var correctCount    = 0
    @State private var sessionComplete = false

    // Session timing
    @State private var sessionStartTime: Date = Date()

    // Insights (computed at session end)
    @State private var initialMastery: [String: Int] = [:]
    @State private var readinessBefore: Int = 0
    @State private var sessionImprovedCount: Int = 0
    @State private var sessionMasteredCount: Int = 0
    @State private var stillWeakItems: [(question: String, mastery: Int)] = []
    @State private var nextReviewHint  = ""
    @State private var scoreAnimated   = false

    enum SwipeResult { case correct, wrong }

    // MARK: - Computed visuals (no logic mutation)

    private var totalCardsInSession: Int { queueManager.queue.count }
    private var remainingCards: Int { max(0, queueManager.queue.count - queueManager.currentIndex) }
    private var sessionProgressPct: Int {
        totalCardsInSession == 0 ? 0
        : Int(Double(queueManager.currentIndex) / Double(totalCardsInSession) * 100)
    }
    private var estimatedMinutesLeft: Int {
        max(1, Int((Double(remainingCards) * 12.0 / 60.0).rounded()))
    }
    private var liveAccuracyPct: Int {
        queueManager.currentIndex > 0
            ? Int(Double(correctCount) / Double(queueManager.currentIndex) * 100)
            : 0
    }
    private var liveAccuracyColor: Color {
        liveAccuracyPct >= 70 ? VerbaTheme.green
        : liveAccuracyPct >= 40 ? VerbaTheme.orange
        : VerbaTheme.danger
    }

    var body: some View {
        ZStack {
            PremiumBackground()
                .ignoresSafeArea()

            if sessionComplete {
                sessionCompleteView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .onAppear { if !sessionComplete { finishSession() } }
            } else if queueManager.didLoad && queueManager.queue.isEmpty {
                emptyStateView
                    .transition(.opacity)
            } else {
                studyView.transition(.opacity)
            }
        }
        .onAppear {
            sessionStartTime = Date()
            queueManager.load(items: document.studyItems, scope: scope)
            captureInitialState()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: sessionComplete)
    }

    // MARK: - Capture Initial State (PRESERVED VERBATIM)

    private func captureInitialState() {
        for item in document.studyItems {
            initialMastery[item.question] = item.mastery
        }
        readinessBefore = ReadinessCalculator.quickScore(
            for: document.studyItems,
            examDate: document.examDate
        )
    }

    // MARK: - Study View (presentation only)

    private var studyView: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 12)

            segmentedProgress
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

            cardStack
                .padding(.horizontal, 20)

            Spacer(minLength: 14)

            controlsArea
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Segmented Progress Bar
    //
    // One tiny capsule per card. Done cards turn green; the current
    // card pulses orange at low opacity so the user sees where they
    // are; remaining cards render as outlines. Caps at 30 segments
    // to keep the bar readable for very long sessions.

    private var segmentedProgress: some View {
        let total      = max(1, totalCardsInSession)
        let visibleCap = 30
        let segments   = min(total, visibleCap)
        let bucketSize = max(1, Int(ceil(Double(total) / Double(segments))))
        let currentBucket = min(max(0, queueManager.currentIndex / bucketSize), segments - 1)
        let filledThrough = min(segments, currentBucket)

        return HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { i in
                Capsule()
                    .fill(
                        i <  filledThrough        ? VerbaTheme.green
                      : i == currentBucket && queueManager.currentIndex < total ? VerbaTheme.orange.opacity(0.55)
                      : VerbaTheme.border
                    )
                    .frame(height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: queueManager.currentIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Session progress: \(sessionProgressPct) percent complete")
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VerbaTheme.muted)
                    .frame(width: 40, height: 40)
                    .background(VerbaTheme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(VerbaTheme.border, lineWidth: 1))
                    .shadow(color: VerbaTheme.shadow(0.04), radius: 6, x: 0, y: 2)
            }
            .accessibilityLabel("Close study session")

            VStack(alignment: .leading, spacing: 3) {
                Text("Study session")
                    .font(VerbaFont.syne(.bold, size: 18))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineLimit(1)
                Text("\(remainingCards) of \(totalCardsInSession) remaining · ~\(estimatedMinutesLeft) min")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                streakPill
                xpPill
            }
        }
    }

    private var streakPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(streakManager.currentStreak > 0 ? VerbaTheme.orange : VerbaTheme.muted)
            Text("\(streakManager.currentStreak)")
                .font(VerbaFont.syne(.bold, size: 12))
                .foregroundStyle(VerbaTheme.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(VerbaTheme.border.opacity(0.6), lineWidth: 1))
        .accessibilityLabel("\(streakManager.currentStreak) day streak")
    }

    private var xpPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(VerbaTheme.green)
            Text("\(xpManager.totalXP)")
                .font(VerbaFont.syne(.bold, size: 12))
                .foregroundStyle(VerbaTheme.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(VerbaTheme.border.opacity(0.6), lineWidth: 1))
        .accessibilityLabel("\(xpManager.totalXP) XP")
    }

    // MARK: - Card Stack (3D flip + reduce-motion fallback)

    private var cardStack: some View {
        ZStack {
            if queueManager.queue.count > queueManager.currentIndex + 2 {
                ghostCard(scale: 0.92, yOffset: 18, opacity: 0.45)
            }
            if queueManager.queue.count > queueManager.currentIndex + 1 {
                ghostCard(scale: 0.96, yOffset: 9, opacity: 0.75)
            }
            if let item = queueManager.currentItem {
                activeCard(item: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(.vertical, 8)
    }

    private func activeCard(item: StudyItem) -> some View {
        ZStack {
            // QUESTION face
            premiumCardSurface(text: item.question,
                               topic: item.topic,
                               isAnswer: false)
                .opacity(showingAnswer ? 0 : 1)

            // ANSWER face: pre-mirrored so the rotation reads correctly
            premiumCardSurface(text: item.answer,
                               topic: item.topic,
                               isAnswer: true)
                .scaleEffect(x: -1, y: 1)
                .opacity(showingAnswer ? 1 : 0)
        }
        .rotation3DEffect(
            reduceMotion ? .zero : Angle(degrees: showingAnswer ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: 0.6
        )
        .offset(cardOffset)
        .rotationEffect(.degrees(cardRotation))
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: showingAnswer)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: cardOffset)
        .onTapGesture {
            guard !showingAnswer else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showingAnswer = true }
            HapticManager.light()
        }
        .gesture(showingAnswer ? swipeGesture : nil)
        .overlay(swipeOverlay)
    }

    // MARK: - Paper Card Surface (typography is the hero)
    //
    // The card is intentionally NOT a giant rounded glass panel. It's a
    // page-like rectangle: cream paper, hairline border, no shadow, no
    // gradient, no floating pill. A serif question/answer is the visual
    // hero. Tiny uppercase captions sit above and below the body text.
    // Mirrors Apple Notes / Things / high-end study-app proportions.

    private func premiumCardSurface(text: String, topic: String, isAnswer: Bool) -> some View {
        VStack(spacing: 0) {
            // Eyebrow row: small topic caption (left) + section marker (right)
            HStack(alignment: .firstTextBaseline) {
                if !topic.isEmpty {
                    Text(topic.uppercased())
                        .font(VerbaFont.syne(.semibold, size: 10))
                        .tracking(1.6)
                        .foregroundStyle(VerbaTheme.muted)
                }
                Spacer(minLength: 8)
                Text(isAnswer ? "ANSWER" : "QUESTION")
                    .font(VerbaFont.syne(.bold, size: 10))
                    .tracking(1.8)
                    .foregroundStyle(isAnswer ? VerbaTheme.green : VerbaTheme.muted)
            }
            .padding(.horizontal, 4)
            .padding(.top, 18)

            // Hero body — serif question/answer, sized to fit
            Text(text)
                .font(VerbaFont.serif(
                    size: text.count > 180 ? 22
                        : text.count > 90  ? 28
                        : text.count > 40  ? 34
                        : 40
                ))
                .foregroundStyle(VerbaTheme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 380, alignment: .center)
                .accessibilityLabel(isAnswer ? "Answer: \(text)" : "Question: \(text)")

            // Bottom caption — just a small uppercase line, no capsule
            HStack(spacing: 6) {
                Image(systemName: isAnswer ? "arrow.left.and.right" : "hand.tap")
                    .font(.system(size: 10, weight: .medium))
                Text(isAnswer ? "swipe or use the buttons to grade" : "tap to reveal")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .tracking(0.5)
            }
            .foregroundStyle(VerbaTheme.muted)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(VerbaTheme.card)
        .overlay(
            Rectangle()
                .stroke(VerbaTheme.border.opacity(0.7), lineWidth: 1)
        )
    }

    private func ghostCard(scale: CGFloat, yOffset: CGFloat, opacity: Double) -> some View {
        // Paper outline only — no fill, no shadow.
        Rectangle()
            .stroke(VerbaTheme.border.opacity(0.45 * opacity), lineWidth: 1)
            .frame(maxWidth: .infinity)
            .frame(height: 460)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(opacity)
    }

    // MARK: - Swipe overlay (PRESERVED semantic — uses same @State vars)

    private var swipeOverlay: some View {
        VStack {
            HStack {
                swipeLabel("missed", color: VerbaTheme.danger, icon: "xmark")
                    .opacity(swipeResult == .wrong ? 1 : max(0, -cardOffset.width / 80))
                Spacer()
                swipeLabel("got it", color: VerbaTheme.green, icon: "checkmark")
                    .opacity(swipeResult == .correct ? 1 : max(0, cardOffset.width / 80))
            }
            .padding(.horizontal, 26)
            .padding(.top, 30)
            Spacer()
        }
    }

    private func swipeLabel(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text.uppercased())
                .font(VerbaFont.syne(.bold, size: 11))
                .tracking(1.0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1.5))
    }

    // MARK: - Swipe gesture (PRESERVED VERBATIM)

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                cardOffset   = value.translation
                cardRotation = Double(value.translation.width / 22)
                swipeResult  = value.translation.width > 40 ? .correct : value.translation.width < -40 ? .wrong : nil
            }
            .onEnded { value in
                if value.translation.width > 100       { commitSwipe(correct: true) }
                else if value.translation.width < -100 { commitSwipe(correct: false) }
                else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        cardOffset = .zero; cardRotation = 0; swipeResult = nil
                    }
                }
            }
    }

    private func commitSwipe(correct: Bool) {
        HapticManager.impact(correct ? .light : .medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            cardOffset   = CGSize(width: correct ? 520 : -520, height: -60)
            cardRotation = correct ? 18 : -18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            recordAnswer(correct: correct)
            withAnimation(.none) { cardOffset = .zero; cardRotation = 0; swipeResult = nil; showingAnswer = false }
        }
    }

    // MARK: - Controls area (presentation only)

    private var controlsArea: some View {
        VStack(spacing: 10) {
            if showingAnswer {
                gradedControls
            } else {
                revealControls
            }
        }
    }

    private var revealControls: some View {
        // Typography-led CTA — no rounded gradient pill. Reads as "next step" in a book.
        VStack(spacing: 14) {
            Button {
                guard !showingAnswer else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showingAnswer = true }
                HapticManager.light()
            } label: {
                HStack(spacing: 12) {
                    Text("Reveal answer")
                    // Phase 19 release wiring — VoiceOver surfaces the
                    // Button's action verb plus a direction-only hint.
                    .accessibilityLabel("Reveal answer")
                    .accessibilityHint("Flips the card to show the answer side.")
                        .font(VerbaFont.serif(size: 22))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(VerbaTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(VerbaTheme.ink.opacity(0.85))
                        .frame(height: 1)
                        .padding(.horizontal, 90)
                }
            }
            .buttonStyle(.plain)

            Text("tap the card, swipe, or use this control.")
                .font(VerbaFont.syne(.regular, size: 11))
                .tracking(0.3)
                .foregroundStyle(VerbaTheme.muted)
        }
    }

    private var gradedControls: some View {
        // Two actions sitting side-by-side like a textbook rating widget.
        // Vertical hairline divides; each side has its own colored accent rule.
        HStack(spacing: 0) {
            Button {
                commitSwipe(correct: false)
            } label: {
                gradedControlLabel(
                    title: "Missed",
                    subtitle: "see it again soon",
                    icon: "arrow.uturn.left",
                    accent: VerbaTheme.danger
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(width: 1, height: 56)

            Button {
                commitSwipe(correct: true)
            } label: {
                gradedControlLabel(
                    title: "Got it",
                    subtitle: "interval extended",
                    icon: "checkmark",
                    accent: VerbaTheme.green
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    private func gradedControlLabel(title: String,
                                    subtitle: String,
                                    icon: String,
                                    accent: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(VerbaFont.serif(size: 19))
            }
            .foregroundStyle(accent)
            Text(subtitle)
                .font(VerbaFont.syne(.regular, size: 10))
                .tracking(0.4)
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent)
                .frame(height: 2)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Empty State (never blank)

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 30)

            // Big illustrated glyph
            ZStack {
                Circle()
                    .fill(VerbaTheme.green.opacity(0.12))
                    .frame(width: 132, height: 132)
                Circle()
                    .fill(VerbaTheme.green.opacity(0.08))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(VerbaTheme.green)
            }

            VStack(spacing: 8) {
                Text("No cards to review")
                    .font(VerbaFont.serif(size: 26))
                    .foregroundStyle(VerbaTheme.ink)
                    .multilineTextAlignment(.center)
                Text("This set has no cards yet — add cards or pick another set to begin a study session.")
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Back to Library")
                        .font(VerbaFont.syne(.bold, size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(VerbaTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: VerbaTheme.shadow(0.18), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)

            Spacer(minLength: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Complete (premium celebration)

    private var sessionCompleteView: some View {
        let total    = queueManager.queue.count
        let accuracy = total > 0 ? Int(Double(correctCount) / Double(total) * 100) : 0
        let headline: String   = accuracy >= 80 ? "crushing it!" : accuracy >= 50 ? "solid session!" : "keep going!"
        let accentColor: Color = accuracy >= 80 ? VerbaTheme.green
                              : accuracy >= 50 ? VerbaTheme.orange
                              : VerbaTheme.danger
        let readinessAfter     = ReadinessCalculator.quickScore(for: document.studyItems, examDate: document.examDate)

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Top close button
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VerbaTheme.muted)
                            .frame(width: 36, height: 36)
                            .background(VerbaTheme.cozySage.opacity(0.85))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(VerbaTheme.border, lineWidth: 1))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 14)

                // Animated progress ring
                ZStack {
                    Circle()
                        .stroke(VerbaTheme.border.opacity(0.6), lineWidth: 12)
                        .frame(width: 168, height: 168)
                    Circle()
                        .trim(from: 0, to: scoreAnimated ? CGFloat(accuracy) / 100.0 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 168, height: 168)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.2, dampingFraction: 0.75).delay(0.1), value: scoreAnimated)

                    VStack(spacing: 2) {
                        Text("\(accuracy)%")
                            .font(VerbaFont.serif(size: 40))
                            .foregroundStyle(accentColor)
                        Text("accuracy")
                            .font(VerbaFont.syne(.medium, size: 12))
                            .foregroundStyle(VerbaTheme.muted)
                            .tracking(1.0)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scoreAnimated = true }
                }
                .padding(.bottom, 18)

                // Mascots + headline
                HStack(spacing: -10) {
                    VerbaMascot(mood: accuracy >= 70 ? .excited : .calm, size: 60)
                    CapyScholar(size: 48)
                }
                .padding(.bottom, 10)

                Text(headline)
                    .font(VerbaFont.serif(size: 28))
                    .foregroundStyle(VerbaTheme.ink)
                    .padding(.bottom, 4)

                Text("\(correctCount)/\(total) correct")
                    .font(VerbaFont.syne(.medium, size: 14))
                    .foregroundStyle(VerbaTheme.muted)
                    .padding(.bottom, 22)

                // XP-earned callout
                xpEarnedCard
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)

                // Stats row
                HStack(spacing: 10) {
                    premiumStat(icon: "checkmark.circle.fill", value: "\(correctCount)",      label: "correct",  color: VerbaTheme.green)
                    premiumStat(icon: "xmark.circle.fill",    value: "\(total-correctCount)", label: "missed",   color: VerbaTheme.danger)
                    premiumStat(icon: "flame.fill",           value: "\(streakManager.currentStreak)d", label: "streak", color: VerbaTheme.orange)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)

                insightsCard(readinessAfter: readinessAfter)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)

                if !nextReviewHint.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                        Text(nextReviewHint)
                            .font(VerbaFont.syne(.medium, size: 13))
                    }
                    .foregroundStyle(VerbaTheme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(VerbaTheme.cozySage.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(VerbaTheme.border.opacity(0.6), lineWidth: 1))
                    .padding(.bottom, 16)
                }

                // Primary CTA
                Button { dismiss() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Continue learning")
                            .font(VerbaFont.syne(.bold, size: 18))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [VerbaTheme.ink, VerbaTheme.ink.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 44)
            }
        }
    }

    private var xpEarnedCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(VerbaTheme.green.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VerbaTheme.green)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("+\(XPManager.XPEvent.studySession.points) XP earned")
                    .font(VerbaFont.syne(.bold, size: 16))
                    .foregroundStyle(VerbaTheme.ink)
                Text("now \(xpManager.totalXP) total · level up from reviewing.")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
            }
            Spacer()
        }
        .padding(16)
        .background(VerbaTheme.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VerbaTheme.green.opacity(0.25), lineWidth: 1)
        )
    }

    private func premiumStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(VerbaFont.syne(.bold, size: 20))
                .foregroundStyle(VerbaTheme.ink)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VerbaTheme.border.opacity(0.7), lineWidth: 1)
        )
    }

    private func insightsCard(readinessAfter: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VerbaTheme.green)
                Text("SESSION BREAKDOWN")
                    .font(VerbaFont.syne(.bold, size: 10))
                    .foregroundStyle(VerbaTheme.muted)
                    .tracking(1.0)
            }
            .padding(.bottom, 14)

            HStack(spacing: 20) {
                insightStat(
                    value: "\(sessionImprovedCount)",
                    label: "cards improved",
                    color: VerbaTheme.green,
                    icon: "arrow.up.circle.fill"
                )
                insightStat(
                    value: "\(sessionMasteredCount)",
                    label: "newly mastered",
                    color: VerbaTheme.green,
                    icon: "checkmark.seal.fill"
                )
            }
            .padding(.bottom, 14)

            if !stillWeakItems.isEmpty {
                Divider().padding(.bottom, 12)

                Text("STILL NEEDS WORK")
                    .font(VerbaFont.syne(.bold, size: 9))
                    .foregroundStyle(VerbaTheme.muted)
                    .tracking(1.0)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stillWeakItems, id: \.question) { weak in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(masteryColor(weak.mastery))
                                .frame(width: 6, height: 6)
                            Text(weak.question)
                                .font(VerbaFont.syne(.regular, size: 13))
                                .foregroundStyle(VerbaTheme.ink)
                                .lineLimit(1)
                            Spacer()
                            Text("\(weak.mastery)%")
                                .font(VerbaFont.syne(.bold, size: 12))
                                .foregroundStyle(masteryColor(weak.mastery))
                        }
                    }
                }
                .padding(.bottom, 14)
            }

            if document.examDate != nil && readinessAfter != readinessBefore {
                Divider().padding(.bottom, 12)

                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(readinessAfter >= readinessBefore ? VerbaTheme.green : VerbaTheme.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exam readiness")
                            .font(VerbaFont.syne(.medium, size: 12))
                            .foregroundStyle(VerbaTheme.muted)
                        HStack(spacing: 6) {
                            Text("\(readinessBefore)%")
                                .font(VerbaFont.syne(.bold, size: 15))
                                .foregroundStyle(VerbaTheme.muted)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11))
                                .foregroundStyle(VerbaTheme.muted)
                            Text("\(readinessAfter)%")
                                .font(VerbaFont.syne(.bold, size: 15))
                                .foregroundStyle(readinessAfter >= readinessBefore ? VerbaTheme.green : VerbaTheme.orange)
                        }
                    }

                    Spacer()

                    if let exam = document.examDate {
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: exam).day ?? 0
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(max(0, days))d left")
                                .font(VerbaFont.syne(.bold, size: 13))
                                .foregroundStyle(days <= 3 ? VerbaTheme.danger : VerbaTheme.orange)
                            Text("to exam")
                                .font(VerbaFont.syne(.regular, size: 11))
                                .foregroundStyle(VerbaTheme.muted)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VerbaTheme.border.opacity(0.7), lineWidth: 1)
        )
    }

    private func insightStat(value: String, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(VerbaFont.syne(.bold, size: 20))
                    .foregroundStyle(VerbaTheme.ink)
                Text(label)
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    private func masteryColor(_ mastery: Int) -> Color {
        mastery >= 80 ? VerbaTheme.green : mastery >= 50 ? VerbaTheme.orange : VerbaTheme.danger
    }

    // MARK: - Logic (PRESERVED VERBATIM)

    private func recordAnswer(correct: Bool) {
        guard let item = queueManager.currentItem else { return }
        StudyScheduler.processAnswer(item: item, correct: correct)
        if correct { correctCount += 1 }
        showingAnswer = false
        queueManager.advance()
        if queueManager.isComplete { finishSession() }
    }

    private func finishSession() {
        guard !sessionComplete else { return }
        computeInsights()
        let total = queueManager.queue.count
        let duration = Date().timeIntervalSince(sessionStartTime)
        let correctPct = total > 0 ? Int(Double(correctCount) / Double(total) * 100) : 0

        SessionTracker.shared.record(
            session: StudySession(date: Date(), cardsReviewed: total, correctCount: correctCount, duration: duration)
        )

        // Phase 18 wiring — record a successful study session to the
        // on-disk analytics log so retention / cohort dashboards have
        // real data. The user.id is SHA256-hashed; never persisted in
        // cleartext.
        var props = AnalyticsManager.EventProps(
            deckID: document.id,
            cardCount: total,
            durationSeconds: duration,
            scorePercent: Double(correctPct),
            source: "flashcard"
        )
        props.result = "success"
        AnalyticsManager.shared.track(
            .studySessionCompleted,
            props: props
        )
        if !AnalyticsManager.shared.isUserActivated {
            AnalyticsManager.shared.track(.firstStudySessionStarted)
        }

        // Streak + notification opt-in trigger. handleStudySessionCompleted
        // is the single entry point that decides whether to surface
        // the in-app rationale overlay the first time a user hits the
        // streak-protect threshold.
        streakManager.recordStudySession()
        Task {
            await NotificationManager.shared.handleStudySessionCompleted(
                daysStudiedAlready: streakManager.todayStudied,
                streakLengthDays: streakManager.currentStreak
            )
        }

        xpManager.award(.studySession)
        HapticManager.success()
        generateReturnIntent()
        sessionComplete = true
    }

    private func computeInsights() {
        let studied = queueManager.queue

        sessionImprovedCount = studied.filter { item in
            let before = initialMastery[item.question] ?? item.mastery
            return item.mastery > before
        }.count

        sessionMasteredCount = studied.filter { item in
            let before = initialMastery[item.question] ?? 0
            return before < 80 && item.mastery >= 80
        }.count

        stillWeakItems = studied
            .filter { $0.mastery < 50 }
            .sorted { $0.mastery < $1.mastery }
            .prefix(3)
            .map { (question: $0.question, mastery: $0.mastery) }
    }

    private func generateReturnIntent() {
        let items = queueManager.queue
        if let intent = ReturnIntent.generate(for: document, studiedItems: items) {
            ReturnIntentStore.shared.save(intent)
            let hours = Int(intent.optimalReturnAt.timeIntervalSinceNow / 3600)
            nextReviewHint = hours < 1  ? "next review in < 1h"
                           : hours < 24 ? "next review in \(hours)h"
                           : "next review in \(hours / 24) day\(hours / 24 == 1 ? "" : "s")"
        } else if let nearest = items.map(\.nextReviewAt).min() {
            let hours = Int(nearest.timeIntervalSinceNow / 3600)
            nextReviewHint = hours < 1 ? "next review in < 1h" : "next review in \(hours)h"
        }
    }
}

