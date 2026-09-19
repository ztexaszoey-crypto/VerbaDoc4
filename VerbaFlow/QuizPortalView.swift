import SwiftUI
import SwiftData

// MARK: - Quiz Mode

enum QuizMode: String, CaseIterable {
    case multipleChoice = "Multiple Choice"
    case openAnswer     = "Open Answer"

    var icon: String {
        switch self {
        case .multipleChoice: return "checkmark.circle.fill"
        case .openAnswer:     return "pencil.line"
        }
    }
}

// MARK: - Quiz Question model

struct QuizQuestion {
    let question: String
    let correctAnswer: String
    let options: [String]         // populated for MC; empty for open answer
}

// MARK: - QuizSetupSheet
// Pre-game settings: pick notes, pick mode, start.

struct QuizSetupSheet: View {
    let allDocuments: [Document]
    @Environment(\.dismiss) private var dismiss

    // Set<String> matches Document.id (Models/Document.swift:9 declares id as String).
    // The previous Set<PersistentIdentifier> was a compile-time error because
    // PersistentIdentifier != String, so selectedIDs.contains(doc.id) and
    // Set(allDocuments.map(\.id)) both failed type-checking.
    @State private var selectedIDs: Set<String> = []
    @State private var mode: QuizMode = .multipleChoice
    @State private var showGame = false

    private var hasDocuments: Bool { !allDocuments.isEmpty }
    private var canStart: Bool { !selectedIDs.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Header mascots
                    HStack(spacing: 4) {
                        CapyScholar(size: 64)
                        CapyScholar(size: 52)
                    }
                    .padding(.top, 8)

                    // No documents error
                    if !hasDocuments {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(VerbaTheme.muted)
                            Text("You need at least one deck to play the Quiz Portal.")
                                .font(VerbaFont.syne(.medium, size: 15))
                                .foregroundStyle(VerbaTheme.muted)
                                .multilineTextAlignment(.center)
                            Text("Go to the Add tab and upload a PDF or paste your notes first.")
                                .font(VerbaFont.syne(.regular, size: 13))
                                .foregroundStyle(VerbaTheme.muted.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(VerbaTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                        .padding(.horizontal, 20)
                    } else {
                        // ── Mode picker ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Text("game mode")
                                .font(VerbaFont.syne(.bold, size: 13))
                                .foregroundStyle(VerbaTheme.muted)
                                .padding(.horizontal, 4)

                            HStack(spacing: 10) {
                                ForEach(QuizMode.allCases, id: \.self) { m in
                                    Button {
                                        HapticManager.light()
                                        mode = m
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: m.icon)
                                            Text(m.rawValue)
                                                .font(VerbaFont.syne(.bold, size: 14))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(mode == m ? VerbaTheme.green : VerbaTheme.card)
                                        .foregroundStyle(mode == m ? .white : VerbaTheme.muted)
                                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                                .stroke(mode == m ? VerbaTheme.green : VerbaTheme.border, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // ── Note selection ────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("choose notes")
                                    .font(VerbaFont.syne(.bold, size: 13))
                                    .foregroundStyle(VerbaTheme.muted)
                                Spacer()
                                Button(selectedIDs.count == allDocuments.count ? "deselect all" : "select all") {
                                    if selectedIDs.count == allDocuments.count {
                                        selectedIDs = []
                                    } else {
                                        selectedIDs = Set(allDocuments.map(\.id))
                                    }
                                }
                                .font(VerbaFont.syne(.medium, size: 12))
                                .foregroundStyle(VerbaTheme.green)
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 8) {
                                ForEach(allDocuments) { doc in
                                    let selected = selectedIDs.contains(doc.id)
                                    let cardCount = doc.studyItems.count
                                    Button {
                                        HapticManager.light()
                                        if selected { selectedIDs.remove(doc.id) }
                                        else         { selectedIDs.insert(doc.id) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(selected ? VerbaTheme.green : VerbaTheme.border)
                                                    .frame(width: 22, height: 22)
                                                if selected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                                                    .font(VerbaFont.syne(.bold, size: 14))
                                                    .foregroundStyle(VerbaTheme.ink)
                                                    .lineLimit(1)
                                                Text("\(cardCount) card\(cardCount == 1 ? "" : "s")")
                                                    .font(VerbaFont.syne(.regular, size: 12))
                                                    .foregroundStyle(VerbaTheme.muted)
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(selected ? VerbaTheme.green.opacity(0.08) : VerbaTheme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                                .stroke(selected ? VerbaTheme.green.opacity(0.4) : VerbaTheme.border, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── Start button ──────────────────────────────────────
                    if hasDocuments {
                        Button {
                            guard canStart else { return }
                            HapticManager.impact()
                            showGame = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bolt.fill")
                                Text(canStart ? "Start Quiz" : "Select at least one deck")
                                    .font(VerbaFont.syne(.bold, size: 17))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(canStart ? VerbaTheme.green : VerbaTheme.border)
                            .foregroundStyle(canStart ? .white : VerbaTheme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                        }
                        .disabled(!canStart)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
                .padding(.top, 8)
            }
            .background(VerbaTheme.bg.ignoresSafeArea())
            .navigationTitle("Quiz Portal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VerbaTheme.muted)
                }
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            let docs = allDocuments.filter { selectedIDs.contains($0.id) }
            QuizGameView(documents: docs, mode: mode)
        }
    }
}

// MARK: - QuizGameView
// Fully blocking quiz screen — cannot be dismissed mid-game.

struct QuizGameView: View {
    let documents: [Document]
    let mode: QuizMode
    @Environment(\.dismiss) private var dismiss

    @State private var questions:      [QuizQuestion] = []
    @State private var currentIndex:   Int = 0
    @State private var score:          Int = 0
    @State private var answered:       Bool = false
    @State private var selectedAnswer: String? = nil
    @State private var openText:       String = ""
    @State private var openCorrect:    Bool? = nil
    @State private var showResults:    Bool = false
    @State private var mascotExcited:  Bool = false
    @FocusState private var textFocused: Bool

    private var current: QuizQuestion? { questions.indices.contains(currentIndex) ? questions[currentIndex] : nil }
    private var progress: Double { questions.isEmpty ? 0 : Double(currentIndex) / Double(questions.count) }

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            if showResults {
                resultsView
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
            } else if let q = current {
                VStack(spacing: 0) {
                    // ── Top bar ───────────────────────────────────────────
                    HStack {
                        Text("\(currentIndex + 1) / \(questions.count)")
                            .font(VerbaFont.syne(.bold, size: 14))
                            .foregroundStyle(VerbaTheme.muted)

                        Spacer()

                        Text("score: \(score)")
                            .font(VerbaFont.syne(.bold, size: 14))
                            .foregroundStyle(VerbaTheme.green)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 56)
                    .padding(.bottom, 12)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(VerbaTheme.border)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(VerbaTheme.green)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    ScrollView {
                        VStack(spacing: 20) {
                            // ── Mascot ────────────────────────────────────
                            HStack(spacing: -4) {
                                VerbaMascot(mood: mascotExcited ? .excited : .happy, size: 56)
                                CapyScholar(size: 44)
                            }

                            // ── Question ──────────────────────────────────
                            Text(q.question)
                                .font(VerbaFont.syne(.bold, size: 18))
                                .foregroundStyle(VerbaTheme.ink)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                                .background(VerbaTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                        .stroke(VerbaTheme.border, lineWidth: 1)
                                )
                                .padding(.horizontal, 20)

                            // ── Answer area ───────────────────────────────
                            if mode == .multipleChoice {
                                multipleChoiceOptions(q: q)
                            } else {
                                openAnswerInput(q: q)
                            }

                            // ── Next button ───────────────────────────────
                            if answered {
                                Button {
                                    HapticManager.impact(.light)
                                    advance()
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(currentIndex + 1 < questions.count ? "Next Question" : "See Results")
                                            .font(VerbaFont.syne(.bold, size: 17))
                                        Image(systemName: "arrow.right")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 17)
                                    .background(VerbaTheme.green)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                                }
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.top, 4)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: answered)
                    }
                }
            }
        }
        .onAppear { buildQuestions() }
        .interactiveDismissDisabled(true) // portal cannot be swiped away
    }

    // MARK: - Multiple choice

    @ViewBuilder
    private func multipleChoiceOptions(q: QuizQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(q.options, id: \.self) { option in
                let isCorrect  = option == q.correctAnswer
                let isSelected = option == selectedAnswer
                let color: Color = {
                    guard answered else { return VerbaTheme.card }
                    if isCorrect            { return VerbaTheme.green.opacity(0.15) }
                    if isSelected           { return VerbaTheme.danger.opacity(0.12) }
                    return VerbaTheme.card
                }()
                let borderColor: Color = {
                    guard answered else { return VerbaTheme.border }
                    if isCorrect            { return VerbaTheme.green }
                    if isSelected           { return VerbaTheme.danger }
                    return VerbaTheme.border
                }()

                Button {
                    guard !answered else { return }
                    selectedAnswer = option
                    answered = true
                    if isCorrect {
                        score += 1
                        mascotExcited = true
                        HapticManager.success()
                    } else {
                        mascotExcited = false
                        HapticManager.impact(.heavy)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(option)
                            .font(VerbaFont.syne(.medium, size: 15))
                            .foregroundStyle(VerbaTheme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if answered {
                            if isCorrect {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(VerbaTheme.green)
                            } else if isSelected {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(VerbaTheme.danger)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                            .stroke(borderColor, lineWidth: 1.5)
                    )
                }
                .disabled(answered)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Open answer

    @ViewBuilder
    private func openAnswerInput(q: QuizQuestion) -> some View {
        VStack(spacing: 12) {
            TextField("Type your answer…", text: $openText, axis: .vertical)
                .font(VerbaFont.syne(.regular, size: 15))
                .padding(14)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .stroke(VerbaTheme.border, lineWidth: 1)
                )
                .focused($textFocused)
                .disabled(answered)

            if !answered {
                Button {
                    guard !openText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    textFocused = false
                    checkOpenAnswer(q: q)
                } label: {
                    Text("Submit Answer")
                        .font(VerbaFont.syne(.bold, size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(VerbaTheme.ink)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                }
            }

            if answered, let correct = openCorrect {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(correct ? VerbaTheme.green : VerbaTheme.danger)
                        Text(correct ? "Correct!" : "Not quite")
                            .font(VerbaFont.syne(.bold, size: 15))
                            .foregroundStyle(correct ? VerbaTheme.green : VerbaTheme.danger)
                    }
                    if !correct {
                        Text("Correct answer:")
                            .font(VerbaFont.syne(.medium, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                        Text(q.correctAnswer)
                            .font(VerbaFont.syne(.bold, size: 14))
                            .foregroundStyle(VerbaTheme.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(correct ? VerbaTheme.green.opacity(0.08) : VerbaTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: answered)
    }

    // MARK: - Results

    private var resultsView: some View {
        let total   = questions.count
        let pct     = total > 0 ? Int(Double(score) / Double(total) * 100) : 0
        let headline: String = pct == 100 ? "Perfect!" : pct >= 80 ? "Great job!" : pct >= 50 ? "Keep studying!" : "More practice needed"

        return VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 4) {
                VerbaMascot(mood: pct >= 80 ? .excited : .thinking, size: 80)
                CapyScholar(size: 64)
            }
            .padding(.bottom, 20)

            Text(headline)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.ink)
                .padding(.bottom, 8)

            Text("\(score) / \(total) correct · \(pct)%")
                .font(VerbaFont.syne(.medium, size: 16))
                .foregroundStyle(VerbaTheme.muted)
                .padding(.bottom, 32)

            HStack(spacing: 12) {
                statBubble(icon: "checkmark.circle.fill", value: "\(score)", label: "correct", color: VerbaTheme.green)
                statBubble(icon: "xmark.circle.fill", value: "\(total - score)", label: "missed", color: VerbaTheme.danger)
                statBubble(icon: "percent", value: "\(pct)", label: "score", color: VerbaTheme.orange)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    HapticManager.impact()
                    buildQuestions()
                    currentIndex   = 0
                    score          = 0
                    answered       = false
                    selectedAnswer = nil
                    openText       = ""
                    openCorrect    = nil
                    showResults    = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.trianglehead.counterclockwise")
                        Text("Play Again")
                            .font(VerbaFont.syne(.bold, size: 17))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(VerbaTheme.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                }

                Button { dismiss() } label: {
                    Text("Done")
                        .font(VerbaFont.syne(.bold, size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VerbaTheme.card)
                        .foregroundStyle(VerbaTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func statBubble(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.ink)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
    }

    // MARK: - Logic

    private func buildQuestions() {
        let allItems = documents.flatMap(\.studyItems).filter {
            !$0.question.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !allItems.isEmpty else { return }

        let allAnswers = allItems.map(\.answer)

        questions = allItems.shuffled().prefix(20).map { item in
            if mode == .multipleChoice {
                let wrong = allAnswers
                    .filter { $0 != item.answer }
                    .shuffled()
                    .prefix(3)
                let opts = ([item.answer] + wrong).shuffled()
                return QuizQuestion(question: item.question, correctAnswer: item.answer, options: opts)
            } else {
                return QuizQuestion(question: item.question, correctAnswer: item.answer, options: [])
            }
        }
    }

    private func checkOpenAnswer(q: QuizQuestion) {
        let userTrimmed    = openText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correctTrimmed = q.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Correct if user answer contains the key words from the correct answer (at least 60% match)
        let correct = userTrimmed == correctTrimmed ||
                      correctTrimmed.contains(userTrimmed) ||
                      userTrimmed.contains(correctTrimmed) ||
                      similarity(userTrimmed, correctTrimmed) >= 0.6
        openCorrect    = correct
        answered       = true
        mascotExcited  = correct
        if correct {
            score += 1
            HapticManager.success()
        } else {
            HapticManager.impact(.heavy)
        }
    }

    private func advance() {
        mascotExcited  = false
        answered       = false
        selectedAnswer = nil
        openText       = ""
        openCorrect    = nil
        if currentIndex + 1 < questions.count {
            currentIndex += 1
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showResults = true
            }
        }
    }

    // Simple word-overlap similarity for open answer checking
    private func similarity(_ a: String, _ b: String) -> Double {
        let aWords = Set(a.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let bWords = Set(b.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        guard !bWords.isEmpty else { return 0 }
        return Double(aWords.intersection(bWords).count) / Double(bWords.count)
    }
}
