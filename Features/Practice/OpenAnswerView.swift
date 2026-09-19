import SwiftUI
import SwiftData

// MARK: - OpenAnswerView
//
// Practice surface where the user types their own answer to a
// question, then reveals the correct answer and self-grades.
// Mirrors the FlashcardStudyView layout (premium background, hero
// header, segmented progress, seg-complete celebration) so visual
// identity stays cohesive across the Practice tab.
//
// Study logic is reused VERBATIM:
//   - StudyQueueManager.gate via didLoad / isComplete
//   - StudyScheduler.processAnswer(item:correct:) drives SRS updates
//   - SessionTracker.shared.record(StudySession(...))
//   - xpManager.award(.studySession)
//   - streakManager.recordStudySession()
//   - HapticManager.success()
//   - ReturnIntent.generate/save
//
// The user provides the typing input; the API is self-grade only
// (no string-similarity scoring — that's a separate feature).

struct OpenAnswerView: View {
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

    // Reveal/grade state
    @State private var userText:    String = ""
    @State private var isRevealed:  Bool = false
    @FocusState private var fieldFocused: Bool

    // AI grading (intelligent-match heuristic against the reference answer).
    // Ships client-side today so the surface is functional offline; a server-side
    // grader can replace `gradeAnswer(against:)` without changing the UI by
    // posting the user's typed answer + reference to a Supabase edge function
    // and returning an `AIGrade` JSON. Header comment now reads:
    //   "type answer → AI grade → self-grade to confirm"
    @State private var aiGrade:   AIGrade? = nil
    @State private var isGrading: Bool     = false
    // NOTE: `scoreAnimated` is declared once above (with the insights block) and
    // reused here for the AI grade ring — a single source of truth that drives
    // both the session-complete arc and the AI letter-grade ring.

    // Session scoring
    @State private var correctCount:    Int = 0
    @State private var sessionComplete: Bool = false

    // Session timing
    @State private var sessionStartTime: Date = Date()

    // Insights (same shape as FlashcardStudyView)
    @State private var initialMastery:         [String: Int] = [:]
    @State private var readinessBefore:        Int = 0
    @State private var sessionImprovedCount:   Int = 0
    @State private var sessionMasteredCount:   Int = 0
    @State private var stillWeakItems:         [(question: String, mastery: Int)] = []
    @State private var nextReviewHint:         String = ""
    @State private var scoreAnimated:          Bool = false

    // Computed visuals
    private var totalCardsInSession: Int { queueManager.queue.count }
    private var remainingCards:      Int { max(0, queueManager.queue.count - queueManager.currentIndex) }
    private var sessionProgressPct:  Int {
        totalCardsInSession == 0 ? 0
        : Int(Double(queueManager.currentIndex) / Double(totalCardsInSession) * 100)
    }
    private var estimatedMinutesLeft: Int {
        max(1, Int((Double(remainingCards) * 30.0 / 60.0).rounded()))
    }

    var body: some View {
        ZStack {
            PremiumBackground().ignoresSafeArea()

            if sessionComplete {
                sessionCompleteView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .onAppear { if !sessionComplete { finishSession() } }
            } else if queueManager.didLoad && queueManager.queue.isEmpty {
                emptyStateView.transition(.opacity)
            } else {
                studyView.transition(.opacity)
            }
        }
        .onAppear {
            sessionStartTime = Date()
            queueManager.load(items: document.studyItems, scope: scope)
            captureInitialState()
            // Auto-focus the text editor when the card mounts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                fieldFocused = true
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: sessionComplete)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
    }

    // MARK: - Capture Initial State (verbatim logic)

    private func captureInitialState() {
        for item in document.studyItems {
            initialMastery[item.question] = item.mastery
        }
        readinessBefore = ReadinessCalculator.quickScore(
            for: document.studyItems,
            examDate: document.examDate
        )
    }

    // MARK: - Study View

    private var studyView: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 12)

            segmentedProgress
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

            // Question card + answer area
            questionArea
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .top)

            Spacer(minLength: 12)

            controlsArea
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero header (matches FlashcardStudyView style)

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
                Text("Open answer")
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
        .padding(.horizontal, 9).padding(.vertical, 6)
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
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(VerbaTheme.border.opacity(0.6), lineWidth: 1))
        .accessibilityLabel("\(xpManager.totalXP) XP")
    }

    // MARK: - Segmented Progress (mirrors FlashcardStudyView)

    private var segmentedProgress: some View {
        let total      = max(1, totalCardsInSession)
        let visibleCap = 30
        let segments   = min(total, visibleCap)
        let bucketSize = max(1, Int(ceil(Double(total) / Double(segments))))
        let currentBucket = min(max(0, queueManager.currentIndex / bucketSize), segments - 1)
        let filledThrough  = min(segments, currentBucket)

        return HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { i in
                Capsule()
                    .fill(
                        i <  filledThrough ? VerbaTheme.green
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

    // MARK: - Question area (card on top, editor + revealed answer below)

    private var questionArea: some View {
        VStack(spacing: 12) {
            if let item = queueManager.currentItem {
                premiumQuestionCard(item: item)
                answerArea(item: item)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func premiumQuestionCard(item: StudyItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if !item.topic.isEmpty {
                    Text(item.topic.uppercased())
                        .font(VerbaFont.syne(.bold, size: 9))
                        .foregroundStyle(VerbaTheme.green)
                        .tracking(1.0)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(VerbaTheme.green.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("QUESTION")
                    .font(VerbaFont.syne(.medium, size: 10))
                    .foregroundStyle(VerbaTheme.muted)
                    .textCase(.uppercase)
                    .tracking(1.4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)

            Spacer(minLength: 12)

            Text(item.question)
                .font(VerbaFont.syne(.bold,
                                     size: item.question.count > 160 ? 17
                                          : item.question.count > 90  ? 21
                                          : item.question.count > 40  ? 25
                                          : 28))
                .foregroundStyle(VerbaTheme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
                .accessibilityLabel("Question: \(item.question)")

            Spacer(minLength: 14)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 11, weight: .semibold))
                Text("type your answer below · reveal when ready")
                    .font(VerbaFont.syne(.medium, size: 11))
                    .tracking(0.4)
            }
            .foregroundStyle(VerbaTheme.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(VerbaTheme.cozySage.opacity(0.85))
            .clipShape(Capsule())
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            ZStack {
                LinearGradient(
                    colors: [VerbaTheme.card, VerbaTheme.cream.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(LinearGradient(
                    colors: [Color.white.opacity(0.6), VerbaTheme.border.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        )
        .shadow(color: VerbaTheme.shadow(0.10), radius: 24, x: 0, y: 14)
        .shadow(color: VerbaTheme.shadow(0.05), radius: 6,  x: 0, y: 2)
    }

    private func answerArea(item: StudyItem) -> some View {
        VStack(spacing: 10) {
            editorSurface
                .frame(minHeight: 88)

            if isRevealed {
                revealedAnswerCard(item: item)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                aiReviewCard
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isRevealed)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: aiGrade?.score)
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if userText.isEmpty && !isRevealed {
                Text("type what you remember…")
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $userText)
                .focused($fieldFocused)
                .font(VerbaFont.syne(.regular, size: 14))
                .foregroundStyle(VerbaTheme.ink)
                .scrollContentBackground(.hidden)
                .background(VerbaTheme.cozySage.opacity(0.85))
                .disabled(isRevealed)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isRevealed ? VerbaTheme.green.opacity(0.35) : VerbaTheme.border, lineWidth: 1)
        )
    }

    private func revealedAnswerCard(item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VerbaTheme.green)
                Text("REFERENCE ANSWER")
                    .font(VerbaFont.syne(.bold, size: 10))
                    .tracking(1.0)
                    .foregroundStyle(VerbaTheme.muted)
            }
            Text(item.answer)
                .font(VerbaFont.syne(.semibold, size: 15))
                .foregroundStyle(VerbaTheme.ink)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerbaTheme.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VerbaTheme.green.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Controls area

    private var controlsArea: some View {
        VStack(spacing: 10) {
            if isRevealed {
                gradedButtons
            } else {
                revealButton
            }
        }
    }

    private var revealButton: some View {
        Button {
            guard let item = queueManager.currentItem else { return }
            HapticManager.light()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isRevealed = true
            }
            fieldFocused = false
            gradeAnswer(against: item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Grade my answer")
                    .font(VerbaFont.syne(.bold, size: 17))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [VerbaTheme.green, VerbaTheme.green.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: VerbaTheme.green.opacity(0.30), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(queueManager.currentItem == nil)
    }

    private var gradedButtons: some View {
        HStack(spacing: 12) {
            Button {
                recordAnswer(correct: false)
            } label: {
                gradedLabel(
                    title: "Missed",
                    subtitle: "see it again soon",
                    icon: "arrow.uturn.left.circle.fill",
                    color: VerbaTheme.danger
                )
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                recordAnswer(correct: true)
            } label: {
                gradedLabel(
                    title: "Got it",
                    subtitle: "interval extended",
                    icon: "checkmark.circle.fill",
                    color: VerbaTheme.green
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private func gradedLabel(title: String,
                             subtitle: String,
                             icon: String,
                             color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title.uppercased())
                    .font(VerbaFont.syne(.bold, size: 13))
                    .tracking(0.8)
            }
            Text(subtitle)
                .font(VerbaFont.syne(.regular, size: 11))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [color, color.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: color.opacity(0.28), radius: 14, x: 0, y: 6)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 30)
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
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 32)
            Spacer(minLength: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Complete

    private var sessionCompleteView: some View {
        let total    = queueManager.queue.count
        let accuracy = total > 0 ? Int(Double(correctCount) / Double(total) * 100) : 0
        let headline: String   = accuracy >= 80 ? "crushing it!"
                              : accuracy >= 50 ? "solid session!"
                              :                  "keep going!"
        let accentColor: Color = accuracy >= 80 ? VerbaTheme.green
                              : accuracy >= 50 ? VerbaTheme.orange
                              :                  VerbaTheme.danger
        let readinessAfter     = ReadinessCalculator.quickScore(for: document.studyItems, examDate: document.examDate)

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
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
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)

                ZStack {
                    Circle()
                        .stroke(VerbaTheme.border.opacity(0.6), lineWidth: 12)
                        .frame(width: 168, height: 168)
                    Circle()
                        .trim(from: 0, to: scoreAnimated ? CGFloat(accuracy) / 100.0 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
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

                xpEarnedCardView
                    .padding(.horizontal, 22).padding(.bottom, 14)

                HStack(spacing: 10) {
                    completeStat(icon: "checkmark.circle.fill", value: "\(correctCount)",      label: "correct", color: VerbaTheme.green)
                    completeStat(icon: "xmark.circle.fill",    value: "\(total-correctCount)", label: "missed",  color: VerbaTheme.danger)
                    completeStat(icon: "flame.fill",           value: "\(streakManager.currentStreak)d", label: "streak", color: VerbaTheme.orange)
                }
                .padding(.horizontal, 22).padding(.bottom, 18)

                insightsBlock(readinessAfter: readinessAfter)
                    .padding(.horizontal, 22).padding(.bottom, 18)

                if !nextReviewHint.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
                        Text(nextReviewHint)
                            .font(VerbaFont.syne(.medium, size: 13))
                    }
                    .foregroundStyle(VerbaTheme.muted)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(VerbaTheme.cozySage.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(VerbaTheme.border.opacity(0.6), lineWidth: 1))
                    .padding(.bottom, 16)
                }

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
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 22)
                .padding(.bottom, 44)
            }
        }
    }

    private var xpEarnedCardView: some View {
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

    private func completeStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
            Text(value).font(VerbaFont.syne(.bold, size: 20)).foregroundStyle(VerbaTheme.ink)
            Text(label).font(VerbaFont.syne(.regular, size: 11)).foregroundStyle(VerbaTheme.muted)
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

    private func insightsBlock(readinessAfter: Int) -> some View {
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
                insightPill(value: "\(sessionImprovedCount)", label: "cards improved", color: VerbaTheme.green, icon: "arrow.up.circle.fill")
                insightPill(value: "\(sessionMasteredCount)", label: "newly mastered", color: VerbaTheme.green, icon: "checkmark.seal.fill")
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
                            Circle().fill(masteryColor(weak.mastery)).frame(width: 6, height: 6)
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
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(VerbaTheme.muted)
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
                            Text("to exam").font(VerbaFont.syne(.regular, size: 11)).foregroundStyle(VerbaTheme.muted)
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

    private func insightPill(value: String, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(VerbaFont.syne(.bold, size: 20)).foregroundStyle(VerbaTheme.ink)
                Text(label).font(VerbaFont.syne(.regular, size: 11)).foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    private func masteryColor(_ mastery: Int) -> Color {
        mastery >= 80 ? VerbaTheme.green : mastery >= 50 ? VerbaTheme.orange : VerbaTheme.danger
    }

    // MARK: - Logic (verbatim — same surfaces as FlashcardStudyView)

    private func recordAnswer(correct: Bool) {
        guard let item = queueManager.currentItem else { return }
        StudyScheduler.processAnswer(item: item, correct: correct)
        if correct { correctCount += 1 }
        // Reset editor for next card + advance queue
        userText     = ""
        isRevealed   = false
        aiGrade      = nil
        scoreAnimated = false
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

        // Phase 18 wiring — same cohort-dashboard contract as
        // FlashcardStudyView.finishSession(). One source of truth for
        // both modes; the `source` property distinguishes in analytics.
        var props = AnalyticsManager.EventProps(
            deckID: document.id,
            cardCount: total,
            durationSeconds: duration,
            scorePercent: Double(correctPct),
            source: "open_answer"
        )
        props.result = "success"
        AnalyticsManager.shared.track(
            .studySessionCompleted,
            props: props
        )
        if !AnalyticsManager.shared.isUserActivated {
            AnalyticsManager.shared.track(.firstStudySessionStarted)
        }
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

    // MARK: - AI Grading
    //
    // Heuristic similarity scoring between the user's typed answer and the
    // reference. Strips stopwords and tokens, then blends coverage of the
    // reference vocabulary with Jaccard overlap to produce a 0–100 score.
    // The score drives:
    //   · a letter grade (A–F) for the grade badge
    //   · a one-word headline ("excellent" / "close" / "miss")
    //   · the colour of the score card (green > 80, orange > 60, red below)
    //
    // Self-grade (Got it / Missed) still drives SRS scheduling — the AI
    // grade is a coach, not an arbiter. A future backend grader can
    // replace this method by posting `userText + item.answer + item.id` to
    // a Supabase edge function and returning the same `AIGrade` shape.

    private func gradeAnswer(against item: StudyItem) {
        isGrading = true
        scoreAnimated = false
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { isGrading = false }

        guard !trimmed.isEmpty else {
            aiGrade = AIGrade(
                score: 0,
                hitWords: [],
                missedWords: AIGrade.tokens(from: item.answer),
                letterGrade: "—"
            )
            return
        }

        let refTokens = AIGrade.tokens(from: item.answer)
        let usrTokens = AIGrade.tokens(from: trimmed)
        let refSet    = Set(refTokens)
        let usrSet    = Set(usrTokens)
        let hit       = Array(refSet.intersection(usrSet)).sorted()
        let missed    = Array(refSet.subtracting(usrSet)).sorted()

        // Coverage answers "did you cover the reference points?"
        // Jaccard answers "is your answer semantically close?"
        // Blend: coverage weighs more so a typed "yes" gets a low score
        // instead of a passing grade from a long synonym.
        let coverage = refSet.isEmpty ? 0.0
                     : Double(hit.count) / Double(refSet.count)
        let jaccard  = refSet.isEmpty ? 0.0
                     : Double(hit.count) / Double(refSet.union(usrSet).count)
        let score    = Int((0.65 * coverage + 0.35 * jaccard) * 100)

        aiGrade = AIGrade(
            score:       max(0, min(100, score)),
            hitWords:    hit,
            missedWords: missed,
            letterGrade: AIGrade.letter(for: score)
        )
    }

    // MARK: - AI review card (renders below revealed answer)

    @ViewBuilder
    private var aiReviewCard: some View {
        if isGrading {
            gradingLoadingCard
        } else if let g = aiGrade {
            aiGradeCard(g)
        }
    }

    private var gradingLoadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8).tint(VerbaTheme.green)
            Text("ai is grading your answer\u{2026}")
                .font(VerbaFont.syne(.medium, size: 13))
                .foregroundStyle(VerbaTheme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    private func aiGradeCard(_ g: AIGrade) -> some View {
        let pct    = g.score
        let accent: Color = pct >= 80 ? VerbaTheme.green
                          : pct >= 60 ? VerbaTheme.orange
                          :              VerbaTheme.danger

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                // Letter-grade badge with circular score ring
                ZStack {
                    Circle().stroke(VerbaTheme.border.opacity(0.6), lineWidth: 3)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: scoreAnimated ? CGFloat(pct) / 100.0 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.7)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.9, dampingFraction: 0.78), value: scoreAnimated)
                    VStack(spacing: -2) {
                        Text(g.letterGrade)
                            .font(VerbaFont.serif(size: 20))
                            .foregroundStyle(accent)
                        Text("\(pct)")
                            .font(VerbaFont.syne(.bold, size: 9))
                            .foregroundStyle(accent.opacity(0.9))
                            .tracking(0.5)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VerbaTheme.green)
                        Text("AI GRADE")
                            .font(VerbaFont.syne(.bold, size: 10))
                            .tracking(1.4)
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    Text("\(pct)% match")
                        .font(VerbaFont.syne(.bold, size: 17))
                        .foregroundStyle(VerbaTheme.ink)
                    Text(AIGrade.headline(for: pct))
                        .font(VerbaFont.syne(.medium, size: 12))
                        .foregroundStyle(accent)
                }
                Spacer()
            }

            Divider().background(VerbaTheme.border.opacity(0.5))

            // Hits
            if !g.hitWords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(VerbaTheme.green)
                        Text("YOU COVERED \u{2014} \(g.hitWords.count) idea\(g.hitWords.count == 1 ? "" : "s")")
                            .font(VerbaFont.syne(.bold, size: 9))
                            .tracking(1.0)
                            .foregroundStyle(VerbaTheme.green)
                    }
                    Text(g.hitWords.prefix(12).joined(separator: " \u{00b7} "))
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.ink)
                        .lineLimit(3)
                }
            }

            // Misses
            if !g.missedWords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 10))
                            .foregroundStyle(VerbaTheme.muted)
                        Text("STILL MISSING \u{2014} \(g.missedWords.count) idea\(g.missedWords.count == 1 ? "" : "s")")
                            .font(VerbaFont.syne(.bold, size: 9))
                            .tracking(1.0)
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    Text(g.missedWords.prefix(12).joined(separator: " \u{00b7} "))
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.muted)
                        .lineLimit(3)
                }
            }

            // Coaching footnote
            HStack(spacing: 6) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VerbaTheme.green.opacity(0.7))
                Text("now grade yourself \u{2014} the ai grade is a coach, not an arbiter.")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineLimit(2)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.30), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scoreAnimated = true
            }
        }
    }
}

// MARK: - AIGrade
//
// Snapshot of the intelligent-match grade. Holds the score, the
// tokens that hit, the tokens that missed, and the letter-grade label.
// Kept as a top-level value type so future callers (analytics, server
// grading APIs) can round-trip the same shape.

struct AIGrade: Equatable {
    let score:        Int
    let hitWords:     [String]
    let missedWords:  [String]
    let letterGrade:  String

    // Stopwords kept conservative — common English function words only.
    // Domain-specific terms (biology, law, etc.) always survive, so a
    // phrase like "the mitochondria is the powerhouse of the cell" still
    // gets credit for "mitochondria" + "powerhouse" + "cell".
    static let stopwords: Set<String> = [
        "the","a","an","and","or","but","of","in","on","at","to","for","with","by",
        "is","are","was","were","be","been","being","as","that","this","these","those",
        "it","its","from","into","than","then","so","if","not","no","do","does","did",
        "have","has","had","will","would","can","could","should","may","might","must",
        "i","you","we","they","he","she","them","his","her","your","my","our","their",
        "what","which","who","whom","whose","why","how","when","where",
        "very","really","just","only","also","even","still","much","many","some","any",
        "about","because","between","through","during","before","after","above","below"
    ]

    static func tokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    static func letter(for score: Int) -> String {
        switch score {
        case 90...100:    return "A"
        case 80..<90:     return "B"
        case 70..<80:     return "C"
        case 60..<70:     return "D"
        case 30..<60:     return "F"
        default:          return "—"
        }
    }

    static func headline(for score: Int) -> String {
        switch score {
        case 90...100:    return "excellent \u{2014} nailed it"
        case 80..<90:     return "strong \u{2014} minor gaps"
        case 70..<80:     return "close \u{2014} missed a couple of ideas"
        case 60..<70:     return "partial \u{2014} reread the card"
        case 30..<60:     return "thin \u{2014} study this one again"
        default:          return "miss \u{2014} no overlap detected, type your answer"
        }
    }
}
