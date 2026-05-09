import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var streakManager: StreakManager
    @Query private var studyItems: [StudyItem]
    
    @State private var isRegenerating = false
    @State private var errorMessage: String? = nil
    @State private var showingRegenerateSheet = false
    @State private var showingExplainSheet: StudyItem? = nil
    
    let document: Document
    
    init(document: Document) {
        self.document = document
        _studyItems = Query(filter: #Predicate<StudyItem> { $0.document == document })
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                documentHeader
                masteryProgressBar
                if studyItems.isEmpty {
                    EmptyCardListView {
                        Task { await regenerateFlashcards() }
                    }
                } else {
                    VStack(spacing: 16) {
                        ForEach(studyItems) { card in
                            FlashcardRow(card: card, onExplain: {
                                showingExplainSheet = card
                                vibrate()
                            })
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                Button {
                    Task { await regenerateFlashcards() }
                } label: {
                    Label("Regenerate Flashcards", systemImage: "arrow.clockwise")
                        .font(VerbaTheme.Font.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(VerbaTheme.green)
                        .foregroundColor(.white)
                        .cornerRadius(14, style: .continuous)
                        .scaleEffectOnPress()
                }
                .padding(.top, 28)
                .disabled(isRegenerating)
                .opacity(isRegenerating ? 0.6 : 1)
                
                if let error = errorMessage {
                    Text(error)
                        .font(VerbaTheme.Font.bodySmall.italic())
                        .foregroundColor(VerbaTheme.red)
                        .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .background(VerbaTheme.background.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingExplainSheet) { card in
            ExplanationSheet(studyItem: card)
        }
    }
    
    // MARK: - Header
    private var documentHeader: some View {
        HStack {
            SourceTypeIcon(type: document.sourceType)
                .frame(maxHeight: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(VerbaTheme.Font.heading1.italic())
                    .foregroundColor(VerbaTheme.textMain)
                HStack(spacing: 12) {
                    Label(dateString(document.createdAt), systemImage: "calendar")
                        .font(VerbaTheme.Font.bodySmall)
                        .foregroundColor(.secondary)
                    Label("\(studyItems.count)", systemImage: "doc.on.doc")
                        .font(VerbaTheme.Font.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(VerbaTheme.card)
        .cornerRadius(20, style: .continuous)
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
    }
    
    private func dateString(_ date: Date?) -> String {
        guard let date else { return "" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }
    
    // MARK: - Mastery Progress Bar
    private var masteryProgressBar: some View {
        let percent: Double = {
            guard studyItems.count > 0 else { return 0 }
            let mastered = studyItems.filter { $0.mastery >= 80 }.count
            return Double(mastered) / Double(studyItems.count)
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Mastery Progress")
                .font(VerbaTheme.Font.heading3)
                .foregroundColor(VerbaTheme.textMain)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(VerbaTheme.card)
                    .frame(height: 18)
                Capsule()
                    .fill(VerbaTheme.green)
                    .frame(width: CGFloat(percent) * 280, height: 18)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: percent)
                Text("\(Int(percent * 100))%")
                    .font(VerbaTheme.Font.bodySmall.bold())
                    .foregroundColor(VerbaTheme.green)
                    .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    // MARK: - Card Row
    private struct FlashcardRow: View {
        @ObservedObject var card: StudyItem
        let onExplain: () -> Void
        @State private var isFlipped = false
        @State private var isExplaining = false
        @State private var explanation: String? = nil
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isFlipped ? card.answer : card.question)
                        .font(isFlipped ? VerbaTheme.Font.body : VerbaTheme.Font.heading2)
                        .foregroundColor(VerbaTheme.textMain)
                        .italic(isFlipped)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isFlipped.toggle()
                        }
                        vibrate()
                    } label: {
                        Image(systemName: isFlipped ? "eye.slash" : "eye")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(VerbaTheme.green)
                    }
                }
                if isFlipped, let explanation = explanation {
                    Text(explanation)
                        .font(VerbaTheme.Font.bodySmall)
                        .foregroundColor(VerbaTheme.textSecondary)
                        .transition(.opacity)
                }
                HStack {
                    Spacer()
                    Button {
                        onExplain()
                        vibrate()
                    } label: {
                        HStack {
                            Image(systemName: "lightbulb")
                            Text("Deep Explain")
                        }
                        .font(VerbaTheme.Font.button)
                        .padding(8)
                        .background(VerbaTheme.gold)
                        .foregroundColor(VerbaTheme.textMain)
                        .cornerRadius(14)
                    }
                }
            }
            .padding(20)
            .background(VerbaTheme.card)
            .cornerRadius(20, style: .continuous)
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFlipped)
        }
    }
    
    // MARK: - Empty State
    private struct EmptyCardListView: View {
        let regenerate: () -> Void
        var body: some View {
            VStack(spacing: 16) {
                Image("capybara-thinking")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                Text("No flashcards yet!")
                    .font(VerbaTheme.Font.heading2.italic())
                    .foregroundColor(VerbaTheme.brown)
                Text("Tap below to let Verba (our study capybara) generate flashcards based on your material.")
                    .font(VerbaTheme.Font.body)
                    .foregroundColor(VerbaTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    regenerate()
                } label: {
                    Label("Generate Flashcards", systemImage: "arrow.triangle.2.circlepath")
                        .font(VerbaTheme.Font.button)
                        .padding(.vertical, 11)
                        .padding(.horizontal, 24)
                        .background(VerbaTheme.green)
                        .foregroundColor(.white)
                        .cornerRadius(14, style: .continuous)
                        .scaleEffectOnPress()
                }
            }
            .padding(.top, 30)
        }
    }
    
    // MARK: - Explanation Sheet
    private struct ExplanationSheet: View {
        let studyItem: StudyItem
        @State private var loading = true
        @State private var explanation: String = ""
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: 24) {
                HStack {
                    Image("capybara-explain")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                    Text("Deep Explanation")
                        .font(VerbaTheme.Font.heading2)
                        .foregroundColor(VerbaTheme.green)
                    Spacer()
                }
                Spacer()
                if loading {
                    ProgressView("Thinking…")
                        .progressViewStyle(CircularProgressViewStyle(tint: VerbaTheme.gold))
                        .padding(.top, 40)
                } else {
                    ScrollView {
                        Text(explanation)
                            .font(VerbaTheme.Font.body)
                            .foregroundColor(VerbaTheme.textMain)
                    }
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(VerbaTheme.Font.button)
                .padding()
                .background(VerbaTheme.green)
                .foregroundColor(.white)
                .cornerRadius(14)
                .scaleEffectOnPress()
            }
            .padding(28)
            .background(VerbaTheme.background.ignoresSafeArea())
            .task {
                await explain()
            }
        }
        private func explain() async {
            loading = true
            defer { loading = false }
            do {
                let result = try await GroqAPI.deepExplain(for: studyItem)
                self.explanation = result
            } catch {
                explanation = "Sorry, Verba got lost in thought. Try again!"
            }
        }
    }
    
    // MARK: - Actions
    
    private func regenerateFlashcards() async {
        isRegenerating = true
        errorMessage = nil
        vibrate()
        do {
            try await StudyGenerator.shared.generateFlashcards(for: document)
        } catch {
            errorMessage = "Something went wrong refreshing your flashcards. Please try again."
        }
        isRegenerating = false
    }
    
    private func vibrate() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
