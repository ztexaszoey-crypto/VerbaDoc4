import SwiftUI
import SwiftData

// MARK: - RefuelSessionView
//
// Shared modal quiz used by TWO entry points into the Capy Surfers flow:
//
//   1. **Pre-game gate** — fullscreen modal that fires before the player
//      is allowed to start a run. The user MUST answer `questionCount`
//      multi-choice questions sourced from their AI-generated StudyItems
//      (Phase 10 conceptual flashcards, NOT cloze). After the gate the
//      capy's energy tank is filled proportional to how many answers
//      were correct: each correct → +5s, each wrong → -5s. A neutral
//      or zero result is fine — the game starts anyway (the gate's job
//      is *engagement*, not gating).
//
//   2. **Launcher top-up button** — small sheet, same quiz flow but with
//      a dismiss X in the corner so the user can always back out. Used
//      to refill the capy's banked energy while the player is mid-session
//      and wants to top up before pressing "Start Run".
//
// The question pool is the same: studyItems from the user's decks,
// shuffled. If the deck is empty the view ports to bundled `DemoTrivia`
// — mirroring `CapySurfersState.demokDeckMCQ` so the demo path works
// even on a fresh install.
//
// IMPORTANT — caller contract:
//   - `state` MUST have called `state.loadQuestions(from: documents)`
//     before this view appears. We rely on that.
struct RefuelSessionView: View {
    @ObservedObject var state: CapySurfersState
    let documents: [Document]
    /// How many questions to serve. Gate uses 3; top-up uses 1.
    let questionCount: Int
    /// Called when `questionCount` answers are in. Gate hands this back
    /// to `CapySurfersGameView.onAppear` so `state.startRun()` runs.
    let onComplete: () -> Void
    /// When true a small "X" appears in the top-trailing corner so the
    /// user can dismiss without finishing. Top-up sheets set true;
    /// the pre-game gate sets false (the brief said "you NEED to answer").
    let allowDismiss: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var challenges: [StudyChallenge] = []
    @State private var index: Int = 0
    @State private var answered: Bool = false
    @State private var selectedIndex: Int? = nil
    @State private var lastWasCorrect: Bool? = nil
    @State private var sessionGains: Int = 0   // count of correct picks
    @State private var sessionLosses: Int = 0   // count of wrong picks

    var body: some View {
        ZStack {
            CozyBackdrop { Color.clear }

            VStack(spacing: 14) {
                header
                progressDots
                if !challenges.isEmpty, index < challenges.count {
                    let c = challenges[index]
                    if case let .multipleChoice(options, ci) = c.kind {
                        questionCard(c: c, options: options, correctIndex: ci)
                    } else {
                        // Defensive fallback. If the StudyChallenge roll
                        // somehow landed on a non-MCQ kind (trueFalse,
                        // flashcardRecall, imageQuestion, diagramID,
                        // matchTheTerm), collapse it to a synthetic MCQ
                        // built from the prompt + answer string. Renders
                        // the same RefuelSessionView UI rather than the
                        // per-kind panel layout we use inside the game.
                        syntheticMCQCard(c: c)
                    }
                }
                Spacer(minLength: 0)
                energyFootprint
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
        }
        .onAppear { buildChallenges() }
        // After tapping an answer, hold 0.9s for the user to read the
        // green/red highlight, then advance to the next question or
        // finish the session. The 0.9s is shorter than the in-game
        // 1.1s because gate flows want snappy pace.
        .onChange(of: answered) { _, isAnswered in
            guard isAnswered else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                advance()
            }
        }
    }

    // MARK: - Header / progress

    private var header: some View {
        HStack(spacing: 8) {
            CapyScholar(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text(headerSubtitle)
                    .font(VerbaFont.syne(.medium, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            if allowDismiss {
                Button { dismissAndComplete() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .padding(9)
                        .background(VerbaTheme.cozySage.opacity(0.85))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerTitle: String {
        questionCount >= 3 ? "Refuel Capy" : "Top Up"
    }
    private var headerSubtitle: String {
        // Phase 16 — drop the redundant percentage metric. The user sees
        // seconds-of-tank only; the bar widget already encodes pct.
        let tank = Int(state.energy)
        return "tank: \(tank)s · +\(secondsPerCorrect) right · -\(secondsPerWrong) wrong"
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<questionCount, id: \.self) { i in
                let isFilled = i < index
                let isCurrent = i == index
                Circle()
                    .fill(isFilled ? VerbaTheme.cozyLime
                          : isCurrent ? VerbaTheme.glossCream
                          : VerbaTheme.glossCream.opacity(0.4))
                    .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                    .overlay(Circle().stroke(VerbaTheme.cozyForest, lineWidth: 1.5))
            }
            Spacer()
            Text("\(sessionGains) right · \(sessionLosses) wrong")
                .font(VerbaFont.syne(.bold, size: 11))
                .foregroundStyle(VerbaTheme.cozyForest)
        }
        .padding(.horizontal, 4)
    }

    private var energyFootprint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VerbaTheme.cozyForest)
            Text("\(Int(state.energy))s / \(Int(CapySurfersState.secondsCap))s")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.cozyForest)
                .contentTransition(.numericText())
            Spacer()
            if !answered {
                Text("pick an answer")
                    .font(VerbaFont.syne(.medium, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke))
    }

    // MARK: - Question card (multi-choice)

    private func questionCard(c: StudyChallenge, options: [String], correctIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(c.prompt)
                .font(VerbaFont.syne(.semibold, size: c.prompt.count > 80 ? 14 : 16))
                .foregroundStyle(VerbaTheme.cozyForest)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .minimumScaleFactor(0.7)

            VStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    optionRow(label: options[i], index: i, correctIndex: correctIndex)
                }
            }
        }
        .padding(18)
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke))
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30), radius: 0, x: 0, y: 5)
    }

    /// Last-resort fallback card. Builds an MCQ from any non-multipleChoice
    /// kind (the gate/top-up questions should always be MCQ after
    /// `buildChallenges` ran, but a future build change could roll a
    /// different kind and we want a graceful fallback rather than an
    /// empty card).
    private func syntheticMCQCard(c: StudyChallenge) -> some View {
        let answerFallback: String = {
            switch c.kind {
            case .flashcardRecall(let a):                  return a
            case .trueFalse(let isTrue):                   return isTrue ? "True" : "False"
            case .imageQuestion(_, let opts, let ci):      return opts.indices.contains(ci) ? opts[ci] : "—"
            case .diagramID(_, let opts, let ci):          return opts.indices.contains(ci) ? opts[ci] : "—"
            case .matchTheTerm(let pairs):                 return pairs.first?.1 ?? "—"
            case .multipleChoice:                          return "—"
            }
        }()
        let faux = c.prompt
        let opts = [answerFallback, "—", "—", "—"]
        return questionCard(
            c: StudyChallenge(kind: .multipleChoice(options: opts, correctIndex: 0),
                              prompt: faux, topic: c.topic, itemID: c.itemID, isBonus: false),
            options: opts,
            correctIndex: 0
        )
    }

    private func optionRow(label: String, index: Int, correctIndex: Int) -> some View {
        let isPicked     = selectedIndex == index
        let isCorrect    = index == correctIndex
        let showFeedback = answered

        let bg: Color = !showFeedback ? VerbaTheme.glossCream.opacity(0.85)
                      : isCorrect      ? VerbaTheme.cozyLime.opacity(0.55)
                      : isPicked       ? VerbaTheme.danger.opacity(0.20)
                      : VerbaTheme.glossCream.opacity(0.85)
        let stroke: Color = !showFeedback ? VerbaTheme.cozyForest.opacity(0.55)
                         : isCorrect     ? VerbaTheme.cozyForest
                         : isPicked      ? VerbaTheme.danger
                         : VerbaTheme.cozyForest.opacity(0.55)
        let fg: Color = VerbaTheme.cozyForest

        return Button {
            guard !answered else { return }
            HapticManager.impact(.light)
            selectedIndex = index
            answered = true
            lastWasCorrect = isCorrect
            // Phase 16 — route through state.submit(_:) so SM-2 mastery
            // writeback fires for items that came from real StudyItems
            // AND the canonical +5s/-5s/0 delta + clamp lives in one
            // place. seed currentChallenge before submit() so the
            // guard `guard let c = currentChallenge else { return }`
            // doesn't bail early. The 1.1s auto-dismiss timer inside
            // state.submit() will nil currentChallenge after we're
            // already showing question N+1 (RefuelSessionView's own
            // 0.9s advance() fires first).
            state.currentChallenge  = challenges[index]
            state.lastAnswer        = nil
            state.challengeResolved = false
            state.quizActive        = true
            state.submit(.index(index))
            if isCorrect { sessionGains += 1 } else { sessionLosses += 1 }
        } label: {
            HStack(spacing: 10) {
                Text(["A","B","C","D"][index])
                    .font(VerbaFont.syne(.bold, size: 11))
                    .foregroundStyle(fg.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(stroke.opacity(0.20))
                    .clipShape(Circle())
                Text(label == "—" ? "(no answer)" : label)
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .foregroundStyle(fg)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if showFeedback {
                    Image(systemName: isCorrect ? "checkmark.circle.fill"
                                  : isPicked ? "xmark.circle.fill" : "circle")
                        .foregroundStyle(isCorrect ? VerbaTheme.cozyForest : isPicked ? VerbaTheme.danger : Color.clear)
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(stroke, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    private var secondsPerCorrect: Double { CapySurfersState.secondsPerCorrect }
    private var secondsPerWrong:   Double { CapySurfersState.secondsPerWrong }

    // MARK: - Lifecycle

    private func buildChallenges() {
        guard challenges.isEmpty else { return }
        // Build a small pool of MCQs from the loaded state. We bypass the
        // `state.triggerChallenge` path because that path goes through
        // the in-game challenge state machine — too heavy for a 3-question
        // gate. Standalone build here keeps the gate UI clean.
        let pool = state.questionPool.isEmpty
            ? documents.flatMap(\.studyItems)
                .filter { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
                .shuffled()
            : state.questionPool.shuffled()

        if pool.isEmpty {
            // Demo deck fallback so the gate / top-up still works on a
            // fresh install with zero StudyItems.
            challenges = (0..<questionCount).map { _ in
                let t = DemoTrivia.random()
                let opts = ([t.answer] + t.distractors).shuffled()
                let ci   = opts.firstIndex(of: t.answer) ?? 0
                return StudyChallenge(
                    kind: .multipleChoice(options: opts, correctIndex: ci),
                    prompt: t.prompt,
                    topic: t.topic,
                    itemID: nil,
                    isBonus: false
                )
            }
        } else {
            challenges = (0..<questionCount).map { _ in
                let item = pool.randomElement()!
                let correct = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidates: [String] = pool
                    .filter { $0.id != item.id }
                    .shuffled()
                    .prefix(3)
                    .map { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0 != correct }
                var opts = Array(candidates.prefix(3))
                while opts.count < 3 { opts.append("—") }
                opts.append(correct)
                let ci = Int.random(in: 0...3)
                opts.swapAt(3, ci)
                return StudyChallenge(
                    kind: .multipleChoice(options: opts, correctIndex: ci),
                    prompt: item.question,
                    topic: item.topic,
                    itemID: item.id,
                    isBonus: false
                )
            }
        }
    }

    private func advance() {
        guard answered else { return }
        if index + 1 < challenges.count {
            index += 1
            answered = false
            selectedIndex = nil
            lastWasCorrect = nil
        } else {
            // Session done — DO NOT touch state.energy directly. The
            // state.submit() calls in optionRow above already moved the
            // tank up/down per user brief; the gate's onComplete handler
            // in CapySurfersGameView then calls completePreRunWarmup()
            // which fills the tank to secondsCap and banks.
            onComplete()
        }
    }

    private func dismissAndComplete() {
        // User dismissed top-up early. Don't refill — just close.
        onComplete()
    }
}
