import SwiftUI

struct TodayPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager

    let items: [StudyItem]
    var sessionTitle: String = "Focus Mode"

    @State private var index = 0
    @State private var showAnswer = false
    @State private var dragOffset: CGSize = .zero
    @State private var sessionStart = Date()
    @State private var reviewedCount = 0
    @State private var didRecordSession = false

    private var currentItem: StudyItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [VerbaTheme.background, VerbaTheme.cream], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if let currentItem {
                VStack(spacing: 20) {
                    header
                    swipeHint
                    focusCard(for: currentItem)
                    controls(for: currentItem)
                    Spacer()
                }
                .padding()
            } else {
                completionView
                    .padding()
            }
        }
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sessionStart = Date() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Card \(min(index + 1, items.count)) of \(items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(index), total: Double(max(items.count, 1)))
                .tint(VerbaTheme.green)
        }
    }

    private var swipeHint: some View {
        HStack {
            Label("Swipe left for Again", systemImage: "arrow.left")
                .accessibilityLabel("Swipe left to rate again")
            Spacer()
            Label("Swipe right for Easy", systemImage: "arrow.right")
                .accessibilityLabel("Swipe right to rate easy")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func focusCard(for item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(showAnswer ? "Answer" : "Question")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(StudyEngine.mastery(for: item))% mastery")
                    .font(.caption.bold())
                    .foregroundStyle(VerbaTheme.green)
            }

            Text(showAnswer ? item.answer : item.question)
                .font(.title2.weight(.bold))
                .foregroundStyle(VerbaTheme.ink)

            if showAnswer {
                Text(item.explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: VerbaTheme.radiusXL, style: .continuous)
                .fill(VerbaTheme.card)
                .shadow(color: VerbaTheme.ink.opacity(0.08), radius: 18, y: 10)
        )
        .rotation3DEffect(.degrees(reduceMotion ? 0 : (showAnswer ? 180 : 0)), axis: (x: 0, y: 1, z: 0))
        .opacity(reduceMotion && showAnswer ? 0.96 : 1.0)
        .offset(dragOffset)
        .rotationEffect(.degrees(Double(dragOffset.width / 18)))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded(handleDrag)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                showAnswer.toggle()
            }
        }
    }

    private func controls(for item: StudyItem) -> some View {
        VStack(spacing: 12) {
            if !showAnswer {
                Button("Flip Card") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        showAnswer = true
                    }
                }
                .buttonStyle(VerbaButtonStyle())
            } else {
                HStack(spacing: 12) {
                    reviewButton("Again", rating: .again, filled: false)
                    reviewButton("Hard", rating: .hard, filled: false)
                }
                HStack(spacing: 12) {
                    reviewButton("Good", rating: .good, filled: true)
                    reviewButton("Easy", rating: .easy, filled: true)
                }

                NavigationLink {
                    TutorView(item: item)
                } label: {
                    Label("Ask Verba", systemImage: "message.fill")
                }
                .buttonStyle(VerbaSecondaryButtonStyle())
            }
        }
    }

    private func reviewButton(_ title: String, rating: ReviewRating, filled: Bool) -> some View {
        Button(title) {
            rateCurrent(rating)
        }
        .buttonStyle(filled ? VerbaButtonStyle() : VerbaSecondaryButtonStyle())
    }

    private var completionView: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🎉")
                .font(.system(size: 72))

            Text("Verba is celebrating!")
                .font(.largeTitle.bold())
                .foregroundStyle(VerbaTheme.ink)

            Text("Capybara-approved session complete. You reviewed \(reviewedCount) cards and earned XP.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                capsuleStat("XP +\(reviewedCount * 10)", color: VerbaTheme.xpGold)
                capsuleStat("Streak \(streakManager.currentStreak)", color: .orange)
            }

            Button("Done") { dismiss() }
                .buttonStyle(VerbaButtonStyle())

            Spacer()
        }
        .onAppear {
            recordSession()
            HapticManager.success()
        }
    }

    private func capsuleStat(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func handleDrag(_ value: DragGesture.Value) {
        guard showAnswer else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                dragOffset = .zero
            }
            return
        }

        if value.translation.width > 120 {
            rateCurrent(.easy)
        } else if value.translation.width < -120 {
            rateCurrent(.again)
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                dragOffset = .zero
            }
        }
    }

    private func rateCurrent(_ rating: ReviewRating) {
        guard let item = currentItem else { return }
        StudyEngine.apply(rating, to: item)
        xpManager.award(.reviewCard)
        reviewedCount += 1
        if reviewedCount == 1 {
            streakManager.markStudyCompleted()
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            dragOffset = .zero
            showAnswer = false
            index += 1
        }
    }

    private func recordSession() {
        guard !didRecordSession else { return }
        let duration = Date().timeIntervalSince(sessionStart)
        guard reviewedCount > 0 else { return }
        SessionTracker.shared.record(
            session: StudySession(
                date: Date(),
                cardsReviewed: reviewedCount,
                correctCount: reviewedCount,
                duration: duration
            )
        )
        xpManager.award(.studySession)
        didRecordSession = true
    }
}
