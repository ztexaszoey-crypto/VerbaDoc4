import SwiftUI
import SwiftData

// MARK: - LibraryView
//
// The Study Dashboard — the personal coach.
// One dominant CTA at all times: the most important thing to do right now.
// Supporting context: exam countdown, memory health, vault.

struct LibraryView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var syncEngine: CloudSyncEngine

    @State private var documentToDelete: Document? = nil

    // Two INDEPENDENT presentation states. Sharing a single optional
    // enum between a `.sheet(item:)` and a `.fullScreenCover(item:)`
    // was the root cause of the "blank white screen on every study
    // mode" bug — when the picker callback mutated `launchPhase =
    // .playing` on the same tick the cover was to be raised, iOS
    // asked the sheet body to re-render with the new nil-matched-
    // case branch (zero children) and did NOT auto-dismiss the
    // sheet, leaving a mounted blank modal blocking the requested
    // cover. Splitting into two bindings lets the modal stack
    // serialize cleanly: the picker callback nils `pickerContext`
    // first (sheet begins dismissing), then queues `studyLaunch`
    // for the next runloop tick so the cover only requests a
    // presentation slot AFTER the sheet is gone. See the picker
    // callback block at the bottom of body().
    /// Delay between sheet-dismissal-init and cover-present so the modal
    /// stack serialises the transition (empirically 0.10s is the sweet
    /// spot for medium/large detents on iPhone 12 -> iPhone 15 Pro).
    private static let coverPresentationDelay: TimeInterval = 0.10

    @State private var pickerContext: StudyLaunchContext? = nil
    @State private var studyLaunch:   StudyLaunch?        = nil
    @State private var showRunnerLauncher: Bool = false
    @State private var runnerDeck:          Document? = nil
    @State private var showCapyGame:        Bool      = false

    @State private var vaultExpanded     = false
    @State private var searchText        = ""
    @State private var debouncedSearch   = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // MARK: - Derived state

    private var activeDocuments: [Document] { documents.filter { !$0.isArchived } }

    private var decision: StudyDecision { StudyDecision.resolve(from: activeDocuments) }

    private var allItems: [StudyItem] { activeDocuments.flatMap(\.studyItems) }

    private var dueCount: Int {
        allItems.filter { $0.nextReviewAt <= Date() }.count
    }

    private var masteredCount: Int { allItems.filter { $0.mastery >= 80 }.count }
    private var learningCount: Int { allItems.filter { $0.mastery >= 50 && $0.mastery < 80 }.count }
    private var atRiskCount:   Int { allItems.filter { $0.mastery < 50 }.count }

    private var estimatedMinutes: Int { max(1, (dueCount * 45 + 59) / 60) }

    private var nearestExam: (document: Document, daysAway: Int)? {
        let now = Date()
        let cal = Calendar.current
        return activeDocuments
            .compactMap { doc -> (Document, Int)? in
                guard let exam = doc.examDate, exam > now else { return nil }
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: exam)).day ?? 0
                return (doc, max(1, days))
            }
            .sorted { $0.1 < $1.1 }
            .first
    }

    private var filtered: [Document] {
        guard !debouncedSearch.isEmpty else { return activeDocuments }
        let q = debouncedSearch.trimmingCharacters(in: .whitespaces)
        return activeDocuments.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.studyItems.contains {
                $0.question.localizedCaseInsensitiveContains(q) ||
                $0.answer.localizedCaseInsensitiveContains(q) ||
                (!$0.topic.isEmpty && $0.topic.localizedCaseInsensitiveContains(q))
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            CozyBackdrop {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        headerSection
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        if syncEngine.isRestoring {
                            restoringState
                        } else if activeDocuments.isEmpty {
                            emptyState
                        } else {
                            // ── Mission (dominant, above fold) ─────────────
                            missionSection
                                .padding(.horizontal, 20)
                                .padding(.bottom, 14)

                            // ── Exam countdown ─────────────────────────────
                            if let exam = nearestExam {
                                examCountdownStrip(exam)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 14)
                            }

                            // ── Memory health (only when there's data) ─────
                            if !allItems.isEmpty {
                                memoryHealthRow
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                            }

                            // ── Daily challenge ────────────────────────────
                            DailyChallengeCard()
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)

                            // ── Vault ──────────────────────────────────────
                            vaultSection
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 120) // clear custom tab bar
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { debouncedSearch = newValue }
                }
            }
            .alert(
                "Delete \"\(documentToDelete?.title ?? "this set")\"?",
                isPresented: Binding(
                    get: { documentToDelete != nil },
                    set: { if !$0 { documentToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let doc = documentToDelete { modelContext.delete(doc); documentToDelete = nil }
                }
                Button("Cancel", role: .cancel) { documentToDelete = nil }
            } message: {
                Text("All \(documentToDelete?.studyItems.count ?? 0) flashcards will be permanently removed.")
            }
        }
        // Launch presentation — TWO independent bindings.
        //   .sheet  watches pickerContext  → renders the mode-picker sheet.
        //   .cover  watches studyLaunch    → renders the chosen study mode.
        // The picker callback below nils pickerContext (= sheet begins
        // dismissing), then queues studyLaunch for the next runloop tick
        // so the cover only requests a presentation slot AFTER the sheet
        // has unmounted. This eliminates the "blank white screen on every
        // study mode" race caused by sharing a single launchPhase binding.
        .sheet(item: $pickerContext) { ctx in
            PracticeModePickerView(document: ctx.document, scope: ctx.scope) { picked in
                let launch = StudyLaunch(
                    document: ctx.document,
                    mode:     picked,
                    scope:    ctx.scope
                )
                // Step 1: dismiss the picker immediately.
                pickerContext = nil
                // Step 2: defer the cover one runloop so the sheet has
                // fully unmounted before the cover asks for a slot.
                // 0.10s is tight enough that the user perceives a single
                // fluid transition, but long enough that the modal stack
                // serializes the dismissal-then-presentation cleanly.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.coverPresentationDelay) {
                    studyLaunch = launch
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $studyLaunch) { launch in
            switch launch.mode {
            case .flashcard:          FlashcardStudyView(document: launch.document, scope: launch.scope)
            case .quizMultipleChoice: Text("We're rebuilding exams with smarter AI distractors. Soon!") // PHASE-2 cull
            case .quizOpenAnswer:     OpenAnswerView(document: launch.document, scope: launch.scope)
            case .studyGuide:         StudyGuideView(document: launch.document, scope: launch.scope)
            }
        }
        .fullScreenCover(isPresented: $showRunnerLauncher) {
            CapyRunnerLaunchView(
                onStartRun: {
                    // Launcher → CapySurfersGameView chain. Pick the
                    // mission-winner deck if decision says so; otherwise
                    // send the first active document so the runner always
                    // has a deck to draw questions from.
                    let deck = decision.document ?? activeDocuments.first
                    // Empty-deck guard: never let the runner open with
                    // zero documents (renders a broken no-question state).
                    // Just close the launcher and leave the user on the
                    // library where the empty state copy is correct.
                    guard let chosen = deck, !activeDocuments.isEmpty else {
                        showRunnerLauncher = false
                        return
                    }
                    runnerDeck = chosen
                    // Defer one runloop tick (coverPresentationDelay) so
                    // the launcher's fullScreenCover fully unmounts before
                    // the runner cover requests a slot — same modal-stack
                    // serialisation trick used by picker/studyLaunch. DO
                    // NOT tighten this value; faster chains on iPhone 12
                    // begin flat-bridging the modal stack and produce the
                    // "blank white screen on every study mode" race this
                    // delay exists to avoid.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.coverPresentationDelay) {
                        showRunnerLauncher = false
                        showCapyGame = true
                    }
                },
                onContinue: {
                    showRunnerLauncher = false
                }
            )
            .environmentObject(xpManager)
            .environmentObject(streakManager)
        }
        .fullScreenCover(isPresented: $showCapyGame) {
            CapySurfersGameView(documents: runnerDeck.map { [$0] } ?? activeDocuments)
                .environmentObject(xpManager)
                .environmentObject(streakManager)
                // Disable swipe-to-dismiss mid-runner so the SM-2 mastery
                // writeback (via CapySurfersResultsView) is never lost on
                // a swipe-down entombing the cover before results land.
                .interactiveDismissDisabled(true)
        }
    }

    // DO NOT MERGE: The picker → cover launch chain relies on TWO
    // independent `@State` (pickerContext + studyLaunch). The original
    // Step-1 bug was that a single shared enum caused the sheet body to
    // re-evaluate with a nil match (zero children) on the same tick the
    // cover asked for a slot, and iOS kept the orphaned sheet mounted
    // instead of dismissing it. Re-merging these would resurrect that
    // "blank white screen on every study mode" bug.

    // MARK: - Header

    private var headerSection: some View {
        CapyHeroPanel(
            mood: streakManager.currentStreak > 0 ? .happy : .calm,
            mascotSize: 56
        ) {
            // Phase 6 brief: Home header HStack puts the greeting on a
            // SINGLE line with status items. .minimumScaleFactor(0.7)
            // scales the greeting down so it never wraps or clips on
            // smaller devices. The runner/play + plus buttons become
            // solid forest-on-cozy lime / sage blocks — no gradients,
            // no gloss, no shadows.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(greeting)
                        .font(VerbaFont.serif(size: 26))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    streakLine
                }

                Spacer()

                HStack(spacing: 10) {
                    // Runner launcher — cozy lime square block
                    Button { showRunnerLauncher = true } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: VerbaTheme.cozyRadius, style: .continuous)
                                    .fill(VerbaTheme.cozyLime)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VerbaTheme.cozyRadius, style: .continuous)
                                            .stroke(VerbaTheme.cozyForest, lineWidth: 3)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open runner launcher")

                    // Add deck — cozy sage square block
                    Button { tabRouter.selected = .upload } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: VerbaTheme.cozyRadius, style: .continuous)
                                    .fill(VerbaTheme.cozySage)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VerbaTheme.cozyRadius, style: .continuous)
                                            .stroke(VerbaTheme.cozyForest, lineWidth: 3)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add new deck")
                }
            }
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        if streakManager.currentStreak > 0 {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VerbaTheme.amber)
                Group {
                    if streakManager.todayStudied {
                        Text("\(streakManager.currentStreak) day streak")
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        + Text(" · done for today ✓")
                            .foregroundStyle(VerbaTheme.cozyLime)
                    } else {
                        Text("\(streakManager.currentStreak) day streak · keep it going")
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                }
                .font(VerbaFont.syne(.regular, size: 13))
            }
        } else if streakManager.totalStudyDays > 0 {
            (Text("comeback. ").foregroundStyle(VerbaTheme.amber).bold()
             + Text("one session gets you back.").foregroundStyle(VerbaTheme.cozyOliveSubtext))
                .font(VerbaFont.syne(.regular, size: 13))
        } else {
            Text("your study dashboard is ready.")
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "good morning."
        case 12..<17: return "good afternoon."
        case 17..<22: return "good evening."
        default:      return "hey."
        }
    }

    // MARK: - Mission Section

    @ViewBuilder
    private var missionSection: some View {
        let d = decision

        switch d {
        case .memoryRisk, .due, .missedWindow, .weak, .fresh:
            if let doc = d.document {
                missionCard(decision: d, document: doc)
            }

        case .allCaughtUp(nextReviewIn: let interval):
            caughtUpCard(interval: interval)

        case .noDecks:
            EmptyView()
        }
    }

    // Premium mission card with left accent bar — Phase 6: cozy block chassis.
    private func missionCard(decision d: StudyDecision, document doc: Document) -> some View {
        let docDue  = doc.studyItems.filter { $0.nextReviewAt <= Date() }.count
        let docWeak = doc.studyItems.filter { $0.mastery < 50 }.count
        let docEst  = max(1, ((docDue > 0 ? docDue : docWeak) * 45 + 59) / 60)
        let readinessPct = ReadinessCalculator.quickScore(for: doc.studyItems, examDate: doc.examDate)

        return VStack(alignment: .leading, spacing: 0) {
            // Top row: chip + time estimate
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: d.chipIcon)
                        .font(.system(size: 9, weight: .bold))
                    Text(d.chipLabel.uppercased())
                        .font(VerbaFont.syne(.bold, size: 10))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
                .foregroundStyle(VerbaTheme.cozyForest)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().stroke(VerbaTheme.cozyForest.opacity(0.40), lineWidth: 1.5)
                )

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("~\(docEst) min")
                        .font(VerbaFont.syne(.medium, size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Deck title — wrapped in VStack per Phase 6 text rules.
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title)
                    .font(VerbaFont.syne(.bold, size: 19))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Text(d.detailLine)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Readiness bar with label
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("readiness")
                        .font(VerbaFont.syne(.medium, size: 11))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text("\(readinessPct)%")
                        .font(VerbaFont.syne(.bold, size: 11))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .lineLimit(1)
                }

                AmberProgressBar(
                    progress: Double(readinessPct) / 100.0,
                    tint: VerbaTheme.cozyLime,
                    height: 8,
                    showsCap: false
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // CTA — sets pickerContext (independent binding) so the
            // sheet that materialises here does not contend with the
            // cover that will present the chosen mode. Phase 6 brief:
            // cozy 3D lime block with text guards.
            Button {
                if case .memoryRisk  = d { ReturnIntentStore.shared.markConsumed() }
                if case .missedWindow = d { ReturnIntentStore.shared.markConsumed() }
                pickerContext = StudyLaunchContext(document: doc, scope: d.drillScope)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                    Text(d.ctaLabel)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(VerbaTheme.cozyForest)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .cozyBlockButtonStyle(fill: VerbaTheme.cozyLime)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .cozyBlockCard(
            fill: VerbaTheme.cozySage,
            ink: VerbaTheme.cozyForest,
            cornerRadius: VerbaTheme.cozyRadius,
            baseOffset: VerbaTheme.cozyOffset,
            strokeWidth: VerbaTheme.cozyStroke
        )
    }

    // All caught up — calm, celebratory. Phase 6: cozy sage block.
    private func caughtUpCard(interval: TimeInterval?) -> some View {
        HStack(spacing: 16) {
            VerbaMascot(mood: .happy, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("all caught up.")
                    .font(VerbaFont.syne(.bold, size: 17))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Text(interval.map { StudyDecision.intervalLabel($0) } ?? "nothing due right now")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(VerbaTheme.cozyForest)
        }
        .padding(18)
        .cozyBlockCard(
            fill: VerbaTheme.cozySage,
            ink: VerbaTheme.cozyForest,
            cornerRadius: VerbaTheme.cozyRadius,
            baseOffset: VerbaTheme.cozyOffset,
            strokeWidth: VerbaTheme.cozyStroke
        )
    }

    // MARK: - Exam Countdown Strip — Phase 6: cozy sage block

    private func examCountdownStrip(_ exam: (document: Document, daysAway: Int)) -> some View {
        let urgent = exam.daysAway <= 3
        let copy = urgent ? "tomorrow" : "in \(exam.daysAway) days"

        return HStack(spacing: 12) {
            Image(systemName: urgent ? "exclamationmark.triangle.fill" : "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VerbaTheme.cozyForest)

            VStack(alignment: .leading, spacing: 4) {
                Text(exam.document.title)
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                Text("exam " + copy)
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }

            Spacer()

            // Urgency chip — sage background, forest outline, no gloss.
            HStack(spacing: 4) {
                Image(systemName: urgent ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.system(size: 11, weight: .bold))
                Text(exam.daysAway == 1 ? "tmrw" : "\(exam.daysAway)d")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .foregroundStyle(VerbaTheme.cozyForest)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(VerbaTheme.cozyLime)
                    .overlay(Capsule().stroke(VerbaTheme.cozyForest, lineWidth: 2.5))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cozyBlockCard(
            fill: VerbaTheme.cozySage,
            ink: VerbaTheme.cozyForest,
            cornerRadius: VerbaTheme.cozyRadius,
            baseOffset: VerbaTheme.cozyOffset,
            strokeWidth: VerbaTheme.cozyStroke
        )
    }

    // MARK: - Memory Health Row

    private var memoryHealthRow: some View {
        // Phase 6: replace ClayStatTile (gradient + shadow) with hand-
        // built cozy sage tiles. Each tile is a solid sage rectangle
        // with a forest 4.5pt stroke; the trio shares the same 3D base.
        HStack(spacing: 10) {
            cozyStatTile(value: masteredCount, label: "mastered", icon: "checkmark.seal.fill")
            cozyStatTile(value: learningCount, label: "learning", icon: "arrow.up.circle.fill")
            cozyStatTile(value: atRiskCount,   label: "at risk",  icon: "exclamationmark.triangle.fill")
        }
    }

    /// Phase 6 helper: matte cozy stat tile (replaces ClayStatTile).
    /// No gradients, no inner highlights, no shadows — just solid
    /// sage fill + 4.5pt forest stroke + offset 3D base.
    private func cozyStatTile(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(VerbaTheme.cozyForest)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(VerbaTheme.cozyLime)
                        .overlay(Circle().stroke(VerbaTheme.cozyForest, lineWidth: 2.5))
                )
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(VerbaTheme.cozyForest)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            Text(label.uppercased())
                .font(VerbaFont.syne(.bold, size: 9))
                .tracking(0.8)
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .cozyBlockCard(
            fill: VerbaTheme.cozySage,
            ink: VerbaTheme.cozyForest,
            cornerRadius: VerbaTheme.cozyRadius,
            baseOffset: VerbaTheme.cozyOffset,
            strokeWidth: VerbaTheme.cozyStroke
        )
    }

    private func healthPill(value: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(VerbaFont.syne(.bold, size: 15))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text(label)
                    .font(VerbaFont.syne(.regular, size: 10))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Vault

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.verba) { vaultExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("your vault")
                        .font(VerbaFont.syne(.semibold, size: 12))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text("· \(activeDocuments.count)")
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    Spacer()
                    Image(systemName: vaultExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext.opacity(0.5))
                }
            }
            .buttonStyle(.plain)

            if vaultExpanded {
                if activeDocuments.count > 2 {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        TextField("search your sets", text: $searchText)
                            .font(VerbaFont.syne(.regular, size: 14))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(VerbaTheme.cozySage)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                            .stroke(VerbaTheme.border, lineWidth: 1)
                    )
                }

                if filtered.isEmpty && !debouncedSearch.isEmpty {
                    Text("nothing found for \"\(debouncedSearch)\"")
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { doc in
                            NavigationLink(destination: DocumentDetailView(document: doc)) {
                                DocumentCard(document: doc)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    documentToDelete = doc
                                } label: {
                                    Label("Delete Set", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty / Restoring States

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            MascotSpeech(
                text: "drop in your notes. i'll build your entire study plan in 30 seconds.",
                mood: .happy,
                mascotSize: 64
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            // Phase 6: cozy 3D lime block (replaces frosted glass slab).
            // Solid fill, 4.5pt forest stroke, offset (4, 5) base.
            Button {
                tabRouter.selected = .upload
            } label: {
                Text("add your first set")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .cozyBlockButtonStyle(fill: VerbaTheme.cozyLime)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 80)
        }
    }

    private var restoringState: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            // Show a static reassuring header above the skeleton stack so
            // the user understands WHY the screen is shimmering. The
            // spinner → skeleton swap keeps the same vertical center.
            VStack(spacing: 6) {
                Text("restoring your library…")
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text("pulling your sets and flashcards from the cloud.")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            // Skeleton placeholder rows. From skeleton -> real content the
            // swap crossfades; using the same .cozyBlockCard chassis means
            // zero layout distance to cover when the real cards resolve.
            SkeletonList(rowCount: 4)
                .padding(.top, 4)

            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
        // Crossfade the skeleton stack once data arrives so the swap
        // doesn't snap. Pairs with SkeletonList's built-in
        // .transition(.opacity.combined(with: .move(edge: .top))).
        .animation(.easeInOut(duration: 0.25), value: syncEngine.isRestoring)
    }
}

// MARK: - DocumentCard

struct DocumentCard: View {
    let document: Document

    private var items: [StudyItem] { document.studyItems }

    private var masteryPct: Int {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.mastery } / items.count
    }

    private var slippingCount: Int { items.filter { $0.nextReviewAt <= Date() }.count }
    private var weakCount:     Int { items.filter { $0.mastery < 50 }.count }

    private var readinessResult: ReadinessCalculator.Result {
        ReadinessCalculator.calculate(for: items, examDate: document.examDate)
    }

    private var readinessColor: Color {
        switch readinessResult.colorKey {
        case .green:  return VerbaTheme.cozyLime
        case .yellow: return VerbaTheme.yellow
        case .orange: return VerbaTheme.orange
        case .red:    return VerbaTheme.danger
        }
    }

    private var nearestDue: Int? {
        let now = Date()
        guard let nearest = items.filter({ $0.nextReviewAt > now }).map(\.nextReviewAt).min() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: now, to: nearest).day ?? 0
        return days <= 7 ? max(1, days) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                        .fill(VerbaTheme.cozySage)
                        .frame(width: 38, height: 38)
                    Image(systemName: document.sourceType.systemIcon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(VerbaTheme.brown)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .lineLimit(1)
                    Text("\(items.count) cards · \(document.sourceType.displayName)")
                        .font(VerbaFont.syne(.regular, size: 11))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }

                Spacer()

                Text(readinessResult.label)
                    .font(VerbaFont.syne(.semibold, size: 10))
                    .foregroundStyle(readinessColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(readinessColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
            }

            // Mastery bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(VerbaTheme.cozyForest.opacity(0.07))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(readinessColor)
                        .frame(width: (CGFloat(masteryPct) / 100) * geo.size.width, height: 3)
                }
            }
            .frame(height: 3)

            HStack(spacing: 0) {
                statPill("\(masteryPct)%", label: "mastery", color: readinessColor)
                if slippingCount > 0 {
                    Spacer()
                    statPill("\(slippingCount)", label: "slipping", color: VerbaTheme.orange)
                } else if let days = nearestDue {
                    Spacer()
                    statPill("in \(days)d", label: "review", color: VerbaTheme.cozyOliveSubtext)
                } else if weakCount > 0 {
                    Spacer()
                    statPill("\(weakCount)", label: "weak", color: VerbaTheme.cozyOliveSubtext)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(VerbaTheme.cozyForest, lineWidth: 3)
            )
        }

        private func statPill(_ value: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value).font(VerbaFont.syne(.bold, size: 12)).foregroundStyle(color)
            Text(label).font(VerbaFont.syne(.regular, size: 11)).foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
    }
}

typealias DocumentRow = DocumentCard
