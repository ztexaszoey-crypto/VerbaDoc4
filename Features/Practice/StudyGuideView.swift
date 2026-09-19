import SwiftUI

// MARK: - StudyGuideView
// A printable-style reference sheet organized by topic.
// Shows mastery bars, key terms, and review hints.

struct StudyGuideView: View {
    let document: Document
    let scope: DrillScope

    // Explicit memberwise init with default. See ExamModeView for why.
    init(document: Document, scope: DrillScope = .all) {
        self.document = document
        self.scope = scope
    }

    @Environment(\.dismiss) private var dismiss

    // Removed `@ObservedObject private var gate = ProGate.shared` —
    // it was never read in this view's body, so it only ever caused
    // dead re-renders on every ProGate change. The paywall surface
    // for study guide is handled at the parent (Library / Practice
    // mode picker), not here.

    // XP + streak are EnvironmentObject-injected from VerbaDocApp.
    // Required for `awardGuideSession()` to compile — these were the
    // invisible deps that the Phase-1 wire-up needed. Without these
    // declarations every reference inside `awardGuideSession()` would
    // resolve to "cannot find 'xpManager'/'streakManager' in scope".
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager

    // Session-duration anchor. `@State` so the date is captured once
    // on `.onAppear` and survives SwiftUI re-inits thereafter; without
    // the @State + .onAppear pair, stored-property defaults re-evaluate
    // on every struct re-init, which would produce nonsense durations
    // under any re-render (Date() != Date() != Date()).
    @State private var viewAppearTime: Date = .init()

    // Step-1 wire-up: route every body-level read of `items`
    // through this scope-filtered computed so due/weak/all filtering from
    // the launch chain actually reaches the rendered guide. The local
    // `items` shadow below names the same collection — chosen to match
    // ExamModeView's vocabulary so the two views stay parallel.
    private var items: [StudyItem] { scope.items(in: document) }

    private var topics: [(name: String, items: [StudyItem])] {
        let ungrouped = items.filter { $0.topic.isEmpty }
        var groups: [(name: String, items: [StudyItem])] = []

        let allTopics = Array(Set(items.compactMap { $0.topic.isEmpty ? nil : $0.topic })).sorted()
        for topic in allTopics {
            let topicItems = items.filter { $0.topic == topic }
            groups.append((name: topic, items: topicItems))
        }
        if !ungrouped.isEmpty {
            groups.append((name: "General", items: ungrouped))
        }
        return groups
    }

    private var overallMastery: Int {
        guard !items.isEmpty else { return 0 }
        return items.map(\.mastery).reduce(0, +) / items.count
    }

    private var strongItems: [StudyItem] {
        items.filter { $0.mastery >= 80 }.sorted { $0.mastery > $1.mastery }
    }

    private var weakItems: [StudyItem] {
        items.filter { $0.mastery < 50 }.sorted { $0.mastery < $1.mastery }
    }

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("back")
                                .font(VerbaFont.syne(.medium, size: 15))
                        }
                        .foregroundStyle(VerbaTheme.ink)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12))
                        Text("study guide")
                            .font(VerbaFont.syne(.bold, size: 14))
                    }
                    .foregroundStyle(VerbaTheme.muted)

                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // ── Overview card ─────────────────────────────────────
                        overviewCard
                            .padding(.horizontal, 20)

                        // ── Priority: weak items ──────────────────────────────
                        if !weakItems.isEmpty {
                            prioritySection
                                .padding(.horizontal, 20)
                        }

                        // ── Topic sections ────────────────────────────────────
                        if !topics.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(VerbaTheme.green)
                                    Text("ALL TOPICS")
                                        .font(VerbaFont.syne(.bold, size: 10))
                                        .tracking(1.8)
                                        .foregroundStyle(VerbaTheme.muted)
                                    Text("— broken down by mastery")
                                        .font(VerbaFont.syne(.regular, size: 11))
                                        .foregroundStyle(VerbaTheme.muted)
                                }
                                .padding(.horizontal, 20)

                                Rectangle()
                                    .fill(VerbaTheme.border.opacity(0.6))
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)

                                VStack(spacing: 28) {
                                    ForEach(topics, id: \.name) { group in
                                        topicCard(group)
                                            .padding(.horizontal, 20)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }

                        // ── Mastered ──────────────────────────────────────────
                        if !strongItems.isEmpty {
                            masteredSection
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 48)

                        // ── "Mark guide complete" CTA (StudyGuide had no
                        // session-end hook otherwise; users can scroll and
                        // leave without ever crediting XP/streak). The
                        // button is the unmissable signal: once tapped, the
                        // session is recorded exactly like the other three
                        // practice modes so XP / streak / mastery / recent
                        // sessions all update from one tap.
                        completeGuideButton
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { viewAppearTime = Date() }
    }

    // MARK: - Complete-Guide CTA + wire-up (Phase 1)

    /// Idempotency guard. Built from `document.id + ISO calendar day` so:
    ///  • re-mounting the same view the same day → no double credit
    ///  • a user who genuinely rewards seven different guides in one
    ///    day each get their own credit
    ///  • a user who re-reads the same guide tomorrow DOES get credit
    ///    again (reading is engagement)
    /// `@State` alone does NOT survive view dismissal — UserDefaults is
    /// the persistent backing.
    private var didAwardGuideToday: Bool {
        UserDefaults.standard.bool(forKey: awardKey(forToday: true))
    }

    private func awardKey(forToday: Bool = true) -> String {
        let day = Self.isoTodayString()
        return "verba.studyGuideAwarded.\(document.id).\(day)"
    }

    private static func isoTodayString() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return fmt.string(from: Date())
    }

    private var completeGuideButton: some View {
        let isDone = didAwardGuideToday
        return Button {
            awardGuideSession()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 15, weight: .bold))
                Text(isDone ? "guide complete" : "mark guide complete")
                    .font(VerbaFont.syne(.bold, size: 17))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(isDone ? VerbaTheme.green : VerbaTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: (isDone ? VerbaTheme.green : Color.black).opacity(0.28),
                    radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isDone)
        .accessibilityLabel(isDone
                            ? "Guide complete. XP and streak already recorded."
                            : "Mark study guide complete to record XP and streak for today.")
    }

    /// Phase-1 wire-up: mirrors `FlashcardStudyView.finishSession()` so
    /// the four practice modes (Flashcard / Open-answer / Exam / Guide)
    /// share one XP+streak+SessionTracker contract. Idempotent across
    /// re-mounts via UserDefaults (`verba.studyGuideAwarded.<docID>.<date>`
    /// — key cleared by resetAwardedGuides() called from StreakManager
    /// notification handler when streak rolls. Mastery is NOT touched:
    /// mastery changes only flow from active answering, never from
    /// passive reading, so SRS rescheduling is never triggered by
    /// "I read this guide".
    private func awardGuideSession() {
        guard !didAwardGuideToday else { return }
        UserDefaults.standard.set(true, forKey: awardKey(forToday: true))

        // Streak credit — same surface as the other three modes.
        streakManager.recordStudySession()

        // XP credit — `award(.studySession)` gives the same delta
        // the Flashcard/OpenAnswer/Exam paths award so the four
        // paths accumulate at equal rates.
        xpManager.award(.studySession)

        // SessionTracker record with `correctCount` set to
        // items.count so cohort dashboards don't read 0% accuracy
        // noise from a "I read this guide" event (every card was
        // reviewed, by definition of engaging the guide in full).
        SessionTracker.shared.record(
            session: StudySession(
                date: Date(),
                cardsReviewed: items.count,
                correctCount: items.count,
                duration: Date().timeIntervalSince(viewAppearTime)
            )
        )

        // Analytics — same `studySessionCompleted` event with a
        // distinct `source` so cohort dashboards can compare modes.
        var props = AnalyticsManager.EventProps(
            deckID: document.id,
            cardCount: items.count,
            durationSeconds: Date().timeIntervalSince(viewAppearTime),
            scorePercent: 100,
            source: "study_guide"
        )
        props.result = "success"
        AnalyticsManager.shared.track(.studySessionCompleted, props: props)

        HapticManager.success()
    }

    /// Anchor for session-duration calc. Set on `.onAppear` of the
    /// view body so StudyGuide.StudySession.duration is meaningful.

    // MARK: - Overview Header (document style — no card wrapper)

    private var overviewCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OVERVIEW")
                        .font(VerbaFont.syne(.bold, size: 10))
                        .tracking(1.8)
                        .foregroundStyle(VerbaTheme.muted)
                    Text(document.title)
                        .font(VerbaFont.serif(size: 26))
                        .foregroundStyle(VerbaTheme.ink)
                        .lineLimit(3)

                    if let exam = document.examDate {
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: exam).day ?? 0
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(days <= 0 ? "exam is today" : "\(days) days to exam")
                                .font(VerbaFont.syne(.semibold, size: 12))
                        }
                        .foregroundStyle(days <= 3 ? VerbaTheme.danger : VerbaTheme.orange)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 14)

                // Overall mastery ring
                ZStack {
                    Circle()
                        .stroke(VerbaTheme.border, lineWidth: 4)
                        .frame(width: 58, height: 58)
                    Circle()
                        .trim(from: 0, to: CGFloat(overallMastery) / 100)
                        .stroke(masteryColor(overallMastery), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 58, height: 58)
                        .rotationEffect(.degrees(-90))
                    Text("\(overallMastery)%")
                        .font(VerbaFont.syne(.bold, size: 12))
                        .foregroundStyle(masteryColor(overallMastery))
                }
            }

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)

            // Stats row — separated by vert hairlines, no card wrap
            HStack(spacing: 0) {
                statCol("\(items.count)", "total cards")
                dividerLine
                statCol("\(topics.count)", "topics")
                dividerLine
                statCol("\(strongItems.count)", "mastered")
                dividerLine
                statCol("\(weakItems.count)", "needs work")
            }

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    // MARK: - Priority: Weak items

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(VerbaTheme.danger)
                Text("PRIORITY REVIEW")
                    .font(VerbaFont.syne(.bold, size: 10))
                    .tracking(1.8)
                    .foregroundStyle(VerbaTheme.danger)
                Text("— study these first")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.muted)
            }

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(weakItems.prefix(8), id: \.id) { item in
                    documentRow(item, highlight: true)
                }
            }

            if weakItems.count > 8 {
                HStack {
                    Spacer()
                    Text("+ \(weakItems.count - 8) more weak cards — study flashcards to see all")
                        .font(VerbaFont.syne(.regular, size: 11))
                        .foregroundStyle(VerbaTheme.muted)
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Topic Section

    private func topicCard(_ group: (name: String, items: [StudyItem])) -> some View {
        let topicMastery = group.items.isEmpty ? 0 : group.items.map(\.mastery).reduce(0, +) / group.items.count

        return VStack(alignment: .leading, spacing: 0) {
            // Topic header — newspaper-style with hairline rule below
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name.uppercased())
                        .font(VerbaFont.syne(.bold, size: 10))
                        .tracking(1.8)
                        .foregroundStyle(VerbaTheme.muted)
                    Text(group.name)
                        .font(VerbaFont.serif(size: 20))
                        .foregroundStyle(VerbaTheme.ink)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(topicMastery)%")
                        .font(VerbaFont.serif(size: 18))
                        .foregroundStyle(masteryColor(topicMastery))
                    Text("\(group.items.count) \(group.items.count == 1 ? "card" : "cards")")
                        .font(VerbaFont.syne(.regular, size: 10))
                        .tracking(0.5)
                        .foregroundStyle(VerbaTheme.muted)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(group.items, id: \.id) { item in
                    documentRow(item, highlight: false)
                }
            }
        }
    }

    // MARK: - Mastered Section

    private var masteredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(VerbaTheme.green)
                Text("MASTERED")
                    .font(VerbaFont.syne(.bold, size: 10))
                    .tracking(1.8)
                    .foregroundStyle(VerbaTheme.muted)
                Text("— \(strongItems.count) \(strongItems.count == 1 ? "card" : "cards") at 80%+")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.muted)
            }

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(strongItems, id: \.id) { item in
                    masteredDocumentRow(item)
                }
            }
        }
    }

    // MARK: - Row helpers (document style)

    private func documentRow(_ item: StudyItem, highlight: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Mastery vertical colour bar — the only colour on the row
            Rectangle()
                .fill(highlight ? VerbaTheme.danger : masteryColor(item.mastery))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.question)
                    .font(VerbaFont.serif(size: 16))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.answer)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text("\(item.mastery)%")
                .font(VerbaFont.syne(.bold, size: 12))
                .foregroundStyle(masteryColor(item.mastery))
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VerbaTheme.border.opacity(0.4))
                .frame(height: 1)
        }
    }

    private func masteredDocumentRow(_ item: StudyItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(VerbaTheme.green)

            Text(item.question)
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.muted)
                .lineLimit(1)

            Spacer()

            Text("\(item.mastery)%")
                .font(VerbaFont.syne(.bold, size: 11))
                .foregroundStyle(VerbaTheme.green)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VerbaTheme.border.opacity(0.4))
                .frame(height: 1)
        }
    }

    // MARK: - Micro-components

    private func statCol(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VerbaFont.serif(size: 22))
                .foregroundStyle(VerbaTheme.ink)
            Text(label.uppercased())
                .font(VerbaFont.syne(.regular, size: 9))
                .tracking(1.2)
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(VerbaTheme.border.opacity(0.6))
            .frame(width: 1, height: 32)
    }

    private func masteryColor(_ mastery: Int) -> Color {
        mastery >= 80 ? VerbaTheme.green : mastery >= 50 ? VerbaTheme.orange : VerbaTheme.danger
    }
}
