import SwiftUI
import SwiftData

// MARK: - QuestionOverlayView
//
// Full-screen quiz overlay shown when a gate obstacle is hit during a run.
// Supports two modes selected by the player in RunLobbyView:
//   • Multiple choice — tap A/B/C/D
//   • Fill in         — type the answer, submit
//
// The chosen mode is stored in @AppStorage("runner.questionMode") so it
// persists across sessions without any extra state threading.

struct QuestionOverlayView: View {

    let card:     StudyItem
    let choices:  [String]           // shuffled; includes the correct answer
    let onAnswer: (Bool) -> Void     // true = correct

    @AppStorage("runner.questionMode") private var questionMode = QuestionMode.multipleChoice

    // MARK: - Timer state

    private let timeLimit: Int = 12
    @State private var secondsLeft: Int    = 12
    @State private var timerTask:   Task<Void, Never>? = nil
    @State private var answered:    Bool   = false

    // MARK: - Multiple-choice state

    @State private var tappedIndex: Int? = nil

    // MARK: - Fill-in state

    @State private var fillText:        String = ""
    @State private var fillResult:      Bool?  = nil   // nil until submitted
    @FocusState private var fillFocused: Bool

    // MARK: - Derived

    private var correctAnswer: String { card.answer }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer(minLength: 0)

                // ── Header ─────────────────────────────────────────────────
                HStack(spacing: 10) {
                    Label("quiz gate", systemImage: "questionmark.circle.fill")
                        .font(VerbaFont.syne(.semibold, size: 12))
                        .foregroundStyle(VerbaTheme.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(VerbaTheme.green.opacity(0.15))
                        .clipShape(Capsule())

                    Spacer()

                    // Countdown ring
                    countdownRing
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)

                // ── Question card ──────────────────────────────────────────
                Text(card.question)
                    .font(VerbaFont.syne(.semibold, size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                // ── Answer area ────────────────────────────────────────────
                Group {
                    if questionMode == .multipleChoice {
                        multipleChoiceArea
                    } else {
                        fillInArea
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
        .onAppear  {
            startTimer()
            if questionMode == .fillIn { fillFocused = true }
        }
        .onDisappear { timerTask?.cancel() }
    }

    // MARK: - Multiple Choice

    private var multipleChoiceArea: some View {
        VStack(spacing: 9) {
            ForEach(Array(choices.enumerated()), id: \.offset) { idx, choice in
                choiceButton(index: idx, choice: choice)
            }
        }
    }

    @ViewBuilder
    private func choiceButton(index: Int, choice: String) -> some View {
        let isCorrect  = choice == correctAnswer
        let isTapped   = tappedIndex == index
        let showResult = answered

        let bg: Color = {
            guard showResult, isTapped else { return .white.opacity(0.08) }
            return isCorrect ? VerbaTheme.green : Color(red: 0.75, green: 0.15, blue: 0.15)
        }()

        let borderColor: Color = {
            if showResult && isCorrect { return VerbaTheme.green }
            if showResult && isTapped  { return Color(red: 0.90, green: 0.30, blue: 0.30) }
            return .white.opacity(0.14)
        }()

        Button {
            guard !answered else { return }
            tappedIndex = index
            answered    = true
            timerTask?.cancel()
            HapticManager.impact()
            let correct = isCorrect
            Task {
                try? await Task.sleep(for: .milliseconds(520))
                await MainActor.run { onAnswer(correct) }
            }
        } label: {
            HStack(spacing: 10) {
                Text(["A","B","C","D"][min(index, 3)])
                    .font(VerbaFont.syne(.bold, size: 11))
                    .foregroundStyle(showResult && isTapped ? .white : .white.opacity(0.45))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.10))
                    .clipShape(Circle())

                Text(choice)
                    .font(VerbaFont.syne(.medium, size: 13))
                    .foregroundStyle(.white.opacity(showResult && isTapped ? 1.0 : 0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showResult && isTapped {
                    Image(systemName: isCorrect ? "checkmark" : "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.18), value: answered)
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    // MARK: - Fill In

    private var fillInArea: some View {
        VStack(spacing: 12) {
            // Text input
            HStack(spacing: 10) {
                TextField("type your answer…", text: $fillText)
                    .font(VerbaFont.syne(.medium, size: 14))
                    .foregroundStyle(.white)
                    .tint(VerbaTheme.green)
                    .focused($fillFocused)
                    .disabled(answered)
                    .onSubmit { submitFillIn() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !fillText.isEmpty && !answered {
                    Button(action: submitFillIn) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(VerbaTheme.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(fillResultBorder, lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.18), value: answered)

            // Result feedback
            if answered, let result = fillResult {
                HStack(spacing: 6) {
                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    if result {
                        Text("correct!")
                            .font(VerbaFont.syne(.semibold, size: 13))
                    } else {
                        Text("answer: \(correctAnswer)")
                            .font(VerbaFont.syne(.semibold, size: 13))
                            .lineLimit(2)
                    }
                }
                .foregroundStyle(result ? VerbaTheme.green : Color(red: 0.90, green: 0.40, blue: 0.40))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.20), value: fillResult)
    }

    private var fillResultBorder: Color {
        guard answered, let result = fillResult else { return .white.opacity(0.14) }
        return result ? VerbaTheme.green : Color(red: 0.90, green: 0.30, blue: 0.30)
    }

    private func submitFillIn() {
        guard !answered, !fillText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        timerTask?.cancel()
        let input   = fillText.trimmingCharacters(in: .whitespaces).lowercased()
        let correct = correctAnswer.lowercased()
        // Accept if the student's answer contains the key term or vice versa
        let isCorrect = input == correct
            || correct.contains(input)
            || input.contains(correct)
        fillResult = isCorrect
        answered   = true
        HapticManager.impact()
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run { onAnswer(isCorrect) }
        }
    }

    // MARK: - Countdown ring

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 3)
                .frame(width: 34, height: 34)
            Circle()
                .trim(from: 0, to: CGFloat(secondsLeft) / CGFloat(timeLimit))
                .stroke(
                    secondsLeft <= 3 ? Color.orange : VerbaTheme.green,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: 34)
                .animation(.linear(duration: 1), value: secondsLeft)
            Text("\(secondsLeft)")
                .font(VerbaFont.syne(.semibold, size: 11))
                .foregroundStyle(.white.opacity(0.60))
        }
    }

    // MARK: - Timer

    private func startTimer() {
        secondsLeft = timeLimit
        answered    = false
        tappedIndex = nil
        fillText    = ""
        fillResult  = nil
        timerTask   = Task {
            for i in stride(from: timeLimit - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { secondsLeft = i }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !answered else { return }
                answered = true
                HapticManager.impact()
                onAnswer(false)
            }
        }
    }
}

// MARK: - Question Mode

enum QuestionMode: String {
    case multipleChoice = "multipleChoice"
    case fillIn         = "fillIn"
}
