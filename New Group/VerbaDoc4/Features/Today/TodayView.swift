import SwiftData
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @Query(sort: \StudyItem.nextReviewAt) private var allItems: [StudyItem]
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]

    @AppStorage("planner.examDate") private var examDateTimestamp: Double = 0

    private var dueItems: [StudyItem] {
        StudyEngine.items(for: .due, from: allItems)
    }

    private var weakItems: [StudyItem] {
        StudyEngine.items(for: .weak, from: allItems)
    }

    private var examDate: Date? {
        examDateTimestamp > 0 ? Date(timeIntervalSince1970: examDateTimestamp) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    heroCard
                    reviewCalendarCard
                    plannerCard
                    weakTopicsCard
                    challengesCard
                }
                .padding()
            }
            .navigationTitle("Today")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Due today")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline) {
                Text("\(dueItems.count)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(VerbaTheme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Predicted grade")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(StudyEngine.predictedGrade(for: allItems))%")
                        .font(.title3.bold())
                        .foregroundStyle(VerbaTheme.green)
                }
            }

            NavigationLink {
                TodayPracticeView(items: dueItems, sessionTitle: "Due Review")
            } label: {
                Label("Start Studying", systemImage: "play.fill")
            }
            .buttonStyle(VerbaButtonStyle())
            .disabled(dueItems.isEmpty)

            if !weakItems.isEmpty {
                NavigationLink {
                    TodayPracticeView(items: weakItems, sessionTitle: "Weak Card Practice")
                } label: {
                    Label("Practice weak cards", systemImage: "bolt.heart.fill")
                }
                .buttonStyle(VerbaSecondaryButtonStyle())
            }
        }
        .verbaCard()
    }

    private var reviewCalendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily review")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(StudyEngine.reviewCalendar(from: allItems)) { day in
                    VStack(spacing: 8) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(day.count)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(day.count > 0 ? VerbaTheme.green.opacity(0.15) : VerbaTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .verbaCard()
    }

    private var plannerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exam planner")
                .font(.headline)

            DatePicker(
                "Exam date",
                selection: Binding(
                    get: { examDate ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date() },
                    set: { examDateTimestamp = $0.timeIntervalSince1970 }
                ),
                displayedComponents: [.date]
            )

            Text(StudyEngine.countdownText(to: examDate))
                .font(.subheadline.bold())
                .foregroundStyle(VerbaTheme.green)

            Text("Recommended daily cards: \(StudyEngine.recommendedDailyCards(for: allItems, examDate: examDate))")
                .font(.subheadline)

            ForEach(StudyEngine.personalizedSchedule(for: allItems, examDate: examDate), id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .verbaCard()
    }

    private var weakTopicsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weak topics")
                .font(.headline)

            let topics = StudyEngine.weakTopics(from: allItems)
            if topics.isEmpty {
                Text("No weak topics right now — keep the streak going.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topics.prefix(3)) { topic in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.topic)
                            Text("\(topic.cardCount) cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(topic.mastery)%")
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .verbaCard()
    }

    private var challengesCard: some View {
        let challenges = ChallengeCenter.challenges(
            documents: documents.count,
            dueCards: dueItems.count,
            weakCards: weakItems.count,
            streak: streakManager.currentStreak,
            xp: xpManager.totalXP
        )

        return VStack(alignment: .leading, spacing: 14) {
            Text("Challenges")
                .font(.headline)

            ForEach(challenges) { challenge in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title)
                            .font(.subheadline.bold())
                        Text(challenge.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if challenge.isClaimed {
                        Text("Claimed")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    } else if challenge.isCompleted {
                        Button("Claim +\(challenge.xpReward) XP") {
                            claim(challenge)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VerbaTheme.green)
                    } else {
                        Text("\(challenge.xpReward) XP")
                            .font(.caption.bold())
                            .foregroundStyle(VerbaTheme.xpGold)
                    }
                }
            }
        }
        .verbaCard()
    }

    private func claim(_ challenge: StudyChallenge) {
        guard !challenge.isClaimed else { return }
        xpManager.award(points: challenge.xpReward)
        ChallengeCenter.claim(challenge)
    }
}
