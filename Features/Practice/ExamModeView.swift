import SwiftUI

// MARK: - ExamModeView (Pro feature)
// Multiple choice exam with timer, scoring, and a results breakdown.
// Four answer options generated from other cards in the deck (distractors).

struct ExamModeView: View {
    let document: Document
    let scope: DrillScope

    // Explicit memberwise init with default. Without this, period-bound
    // Xcode/Swift builds can show 'Extra argument ' scope ' in call' when
    // an inline-default property is not exposed by the synthesized
    // memberwise init. Default `.all` keeps the legacy
    // `ExamModeView(document:)` call sites compiling.
    init(document: Document, scope: DrillScope = .all) {
        self.document = document
        self.scope = scope
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var xpManager: XPManager

    // State
    @State private var questions:    [ExamQuestion] = []
    @State private var currentIndex: Int = 0
    @State private var selected:     Int? = nil          // index of tapped option
    @State private var revealed:     Bool = false        // show correct/wrong
    @State private var score:        Int = 0
    @State private var timeLeft:     Int = 30
    @State private var timerTask:    Task<Void, Never>? = nil
    @State private var done:         Bool = false
    @State private var shake:        Bool = false
    @State private var pulse:        Bool = false    // Colours for options — intentionally absent. The redesign uses a
    // monochromatic SAT-style layout (no pastel pools) so a real
    // selected/reveal state reads with clear intent instead of indistinct
    // coloured pools.
    private static let optionLetters: [String] = ["A", "B", "C", "D"]

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            if done {
                resultsView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            } else if questions.isEmpty {
                loadingView
            } else {
                questionView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .onAppear { buildQuestions() }
        .onDisappear { timerTask?.cancel() }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: done)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: currentIndex)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            if document.studyItems.count < 4 {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(VerbaTheme.muted)
                Text("need at least 4 cards for exam mode")
                    .font(VerbaFont.syne(.medium, size: 15))
                    .foregroundStyle(VerbaTheme.muted)
                    .multilineTextAlignment(.center)
                Button("go back") { dismiss() }
                    .font(VerbaFont.syne(.semibold, size: 15))
                    .foregroundStyle(VerbaTheme.green)
            } else {
                ProgressView()
                    .tint(VerbaTheme.green)
                    .scaleEffect(1.4)
                Text("building your exam…")
                    .font(VerbaFont.syne(.medium, size: 15))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
        .padding(32)
    }

    // MARK: - Question View

    private var questionView: some View {
        VStack(spacing: 0) {

            // ── Header bar ────────────────────────────────────────────────
            examHeader

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // ── Question card ─────────────────────────────────────
                    questionCard
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    // ── Options ───────────────────────────────────────────
                    optionsGrid
                        .padding(.horizontal, 20)

                    Spacer(minLength: 32)
                }
            }
        }
    }

    private var examHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button { endExam() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VerbaTheme.muted)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End exam")

                Spacer()

                // Question counter
                Text("\(currentIndex + 1) / \(questions.count)")
                    .font(VerbaFont.syne(.bold, size: 15))
                    .foregroundStyle(VerbaTheme.ink)
                    .tracking(0.4)

                Spacer()

                // Timer ring
                timerRing
            }
            .padding(.horizontal, 20)

            // Progress bar — thin rectangular rule, no rounded gradient chunk
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(VerbaTheme.border.opacity(0.7))
                        .frame(height: 2)
                    Rectangle()
                        .fill(VerbaTheme.green)
                        .frame(
                            width: geo.size.width * CGFloat(currentIndex) / CGFloat(max(questions.count, 1)),
                            height: 2
                        )
                        .animation(.spring(response: 0.4), value: currentIndex)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(VerbaTheme.bg)
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(VerbaTheme.border, lineWidth: 3)
                .frame(width: 38, height: 38)

            Circle()
                .trim(from: 0, to: CGFloat(timeLeft) / 30.0)
                .stroke(
                    timerColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 38, height: 38)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timeLeft)

            Text("\(timeLeft)")
                .font(VerbaFont.syne(.bold, size: 13))
                .foregroundStyle(timerColor)
        }
    }

    private var timerColor: Color {
        timeLeft > 15 ? VerbaTheme.green
            : timeLeft > 7 ? VerbaTheme.orange
            : VerbaTheme.danger
    }

    private var questionCard: some View {
        let q = questions[currentIndex]
        // Document-style question header floating on the page — no card, no shadow.
        return VStack(spacing: 14) {
            if !q.topic.isEmpty {
                Text(q.topic.uppercased())
                    .font(VerbaFont.syne(.bold, size: 10))
                    .tracking(1.8)
                    .foregroundStyle(VerbaTheme.muted)
            }

            // Tiny eyebrow marker showing question number in this exam.
            Text("QUESTION \(currentIndex + 1)")
                .font(VerbaFont.syne(.bold, size: 9))
                .tracking(1.8)
                .foregroundStyle(VerbaTheme.green)

            Text(q.question)
                .font(VerbaFont.serif(size: 24))
                .foregroundStyle(VerbaTheme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)
                .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .offset(x: shake ? -8 : 0)
        .animation(
            shake ? .default.repeatCount(4, autoreverses: true).speed(8) : .default,
            value: shake
        )
    }

    private var optionsGrid: some View {
        let q = questions[currentIndex]
        return VStack(spacing: 12) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                optionButton(text: option, index: i, correctIndex: q.correctIndex)
            }
        }
    }

    private func optionButton(text: String, index: Int, correctIndex: Int) -> some View {
        let isSelected  = selected == index
        let isCorrect   = index == correctIndex
        let isWrong     = isSelected && !isCorrect && revealed

        let fillColor: Color = {
            if revealed {
                if isCorrect { return VerbaTheme.green.opacity(0.08) }
                if isWrong   { return VerbaTheme.danger.opacity(0.06) }
                return .clear                                          // unselected after reveal
            }
            return isSelected ? VerbaTheme.green.opacity(0.06) : .clear
        }()

        let borderColor: Color = {
            if revealed {
                if isCorrect { return VerbaTheme.green.opacity(0.7) }
                if isWrong   { return VerbaTheme.danger.opacity(0.7) }
                return VerbaTheme.border.opacity(0.5)
            }
            return isSelected ? VerbaTheme.green.opacity(0.7) : VerbaTheme.border.opacity(0.7)
        }()

        let textColor: Color = {
            if revealed && !isCorrect && !isWrong { return VerbaTheme.muted }
            return VerbaTheme.ink
        }()

        let letterColor: Color = {
            if revealed {
                if isCorrect { return VerbaTheme.green }
                if isWrong   { return VerbaTheme.danger }
                return VerbaTheme.muted
            }
            return isSelected ? VerbaTheme.green : VerbaTheme.muted
        }()

        let accentColor: Color = {
            if revealed && isCorrect { return VerbaTheme.green }
            if revealed && isWrong   { return VerbaTheme.danger }
            if !revealed && isSelected { return VerbaTheme.green }
            return .clear
        }()

        return Button {
            guard !revealed else { return }
            HapticManager.light()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selected = index
                revealed = true
            }
            if isCorrect {
                score += 1
                HapticManager.success()
                pulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pulse = false }
            } else {
                HapticManager.impact(.medium)
                shake = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shake = false }
            }
            // Advance after short delay
            timerTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { advance() }
        } label: {
            HStack(spacing: 0) {
                // Left vertical accent bar — only visible when interesting.
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)

                // Letter prefix — plain bold typography, no circle wrapper.
                Text(Self.optionLetters[index % 4])
                    .font(VerbaFont.syne(.bold, size: 14))
                    .tracking(1.0)
                    .frame(width: 38, alignment: .leading)
                    .padding(.leading, 14)
                    .foregroundStyle(letterColor)

                // Vertical hairline between letter and content (test-paper feel).
                Rectangle()
                    .fill(VerbaTheme.border.opacity(0.5))
                    .frame(width: 1, height: 26)

                Text(text)
                    .font(VerbaFont.syne(.medium, size: 16))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // Result gaze (after reveal)
                if revealed {
                    Image(systemName: isCorrect ? "checkmark" : (isWrong ? "xmark" : "circle"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isCorrect ? VerbaTheme.green : (isWrong ? VerbaTheme.danger : VerbaTheme.muted))
                        .padding(.trailing, 14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fillColor)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isSelected && pulse ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(revealed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: revealed)
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {

            // Close button
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VerbaTheme.muted)
                        .padding(9)
                        .background(VerbaTheme.card)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(VerbaTheme.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {

                    // Score ring
                    scoreRing
                        .padding(.top, 16)

                    // Headline
                    let pct = questions.isEmpty ? 0 : Int(Double(score) / Double(questions.count) * 100)
                    VStack(spacing: 8) {
                        Text(pct >= 80 ? "exam ready!" : pct >= 60 ? "almost there" : "keep grinding")
                            .font(VerbaFont.serif(size: 28))
                            .foregroundStyle(VerbaTheme.ink)

                        Text("\(score) of \(questions.count) correct · \(pct)% score")
                            .font(VerbaFont.syne(.medium, size: 15))
                            .foregroundStyle(VerbaTheme.muted)
                    }

                    // Stats cards
                    HStack(spacing: 12) {
                        resultStat(icon: "checkmark.circle.fill", value: "\(score)",                  label: "correct",  color: VerbaTheme.green)
                        resultStat(icon: "xmark.circle.fill",     value: "\(questions.count - score)", label: "wrong",    color: VerbaTheme.danger)
                        resultStat(icon: "percent",               value: "\(pct)%",                   label: "score",    color: VerbaTheme.orange)
                    }
                    .padding(.horizontal, 20)

                    // Question review
                    VStack(alignment: .leading, spacing: 10) {
                        Text("review")
                            .font(VerbaFont.syne(.bold, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                            .textCase(.uppercase)
                            .tracking(1)
                            .padding(.leading, 4)

                        ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                            reviewRow(q, number: i + 1)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Done button
                    Button("done") { dismiss() }
                        .font(VerbaFont.syne(.bold, size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(VerbaTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                        .shadow(color: VerbaTheme.green.opacity(0.3), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }
        }
    }

    private var scoreRing: some View {
        let pct = questions.isEmpty ? 0.0 : Double(score) / Double(questions.count)
        let color: Color = pct >= 0.8 ? VerbaTheme.green : pct >= 0.6 ? VerbaTheme.orange : VerbaTheme.danger

        return ZStack {
            Circle()
                .stroke(VerbaTheme.border, lineWidth: 10)
                .frame(width: 130, height: 130)

            Circle()
                .trim(from: 0, to: pct)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.2), value: done)

            VStack(spacing: 2) {
                Text("\(Int(pct * 100))%")
                    .font(VerbaFont.syne(.bold, size: 28))
                    .foregroundStyle(color)
                Text("score")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    private func resultStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(VerbaFont.syne(.bold, size: 22))
                .foregroundStyle(VerbaTheme.ink)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous).stroke(VerbaTheme.border, lineWidth: 1))
    }

    private func reviewRow(_ q: ExamQuestion, number: Int) -> some View {
        let wasCorrect = q.userAnswer == q.correctIndex
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(wasCorrect ? VerbaTheme.green : VerbaTheme.danger)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(q.question)
                    .font(VerbaFont.syne(.medium, size: 13))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineLimit(2)

                Text(q.options[q.correctIndex])
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(wasCorrect ? VerbaTheme.green.opacity(0.3) : VerbaTheme.danger.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Logic

    private func buildQuestions() {
        // Step-1 wire-up: respect the DrillScope from the launch chain
        // so "study all 14 due cards" actually means "study the 4 due cards".
        let items = scope.items(in: document).shuffled()
        guard items.count >= 4 else { return }

        questions = items.prefix(min(items.count, 15)).map { item in
            // Build 3 distractors from other items' answers
            let others = items.filter { $0.id != item.id }.shuffled().prefix(3).map(\.answer)
            var opts   = Array(others) + [item.answer]
            opts.shuffle()
            let correctIdx = opts.firstIndex(of: item.answer) ?? 0

            return ExamQuestion(
                question:     item.question,
                options:      opts,
                correctIndex: correctIdx,
                topic:        item.topic,
                userAnswer:   nil
            )
        }

        startTimer()
    }

    private func startTimer() {
        timeLeft = 30
        timerTask?.cancel()
        timerTask = Task {
            while timeLeft > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { timeLeft -= 1 }
            }
            if timeLeft == 0 && !Task.isCancelled { advance() }
        }
    }

    private func advance() {
        timerTask?.cancel()
        let nextIndex = currentIndex + 1
        if nextIndex >= questions.count {
            withAnimation { done = true }
            xpManager.award(.studySession)
            HapticManager.success()
        } else {
            withAnimation { currentIndex = nextIndex; selected = nil; revealed = false }
            startTimer()
        }
    }

    private func endExam() {
        timerTask?.cancel()
        dismiss()
    }
}

// MARK: - ExamQuestion

struct ExamQuestion {
    let question:     String
    let options:      [String]
    let correctIndex: Int
    let topic:        String
    var userAnswer:   Int?
}
