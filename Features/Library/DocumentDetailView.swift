import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var streakManager: StreakManager
    @Query private var studyItems: [StudyItem]
    
    @State private var isRegenerating = false
    @State private var errorMessage: String? = nil
    @State private var showingExplainSheet: StudyItem? = nil
    
    let document: Document
    
    init(document: Document) {
        self.document = document
        _streakManager = State(initialValue: StreakManager())
        _studyItems = Query(filter: #Predicate<StudyItem> { $0.document == document })
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.95),
                    Color(red: 0.99, green: 0.98, blue: 0.97)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    documentHeader
                        .padding(.top, 20)
                    
                    masteryProgressSection
                        .padding(.horizontal, 20)
                    
                    statsCards
                        .padding(.horizontal, 20)
                    
                    contentSection
                        .padding(.horizontal, 20)
                    
                    actionButtons
                        .padding(.horizontal, 20)
                    
                    if let error = errorMessage {
                        errorBanner(error)
                            .padding(.horizontal, 20)
                    }
                    
                    Color.clear.frame(height: 20)
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingExplainSheet) { card in
            ExplanationSheet(studyItem: card)
        }
    }
    
    // MARK: - Document Header
    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    sourceTypeIcon(document.sourceType)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundColor(.black)
                        .lineLimit(2)
                    
                    HStack(spacing: 16) {
                        Label(dateString(document.createdAt), systemImage: "calendar")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.gray)
                        
                        Label("\(studyItems.count) cards", systemImage: "rectangle.stack")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Mastery Progress
    private var masteryProgressSection: some View {
        let percent: Double = {
            guard studyItems.count > 0 else { return 0 }
            let mastered = studyItems.filter { $0.mastery >= 80 }.count
            return Double(mastered) / Double(studyItems.count)
        }()
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mastery Progress")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.black)
                    
                    Text("\(Int(percent * 100))% of cards mastered")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    
                    Circle()
                        .trim(from: 0, to: percent)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.8, blue: 0.4),
                                    Color(red: 0.0, green: 0.7, blue: 0.3)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: percent)
                    
                    Text("\(Int(percent * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                .frame(width: 64, height: 64)
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
    }
    
    // MARK: - Stats Cards
    private var statsCards: some View {
        let masteryLevels = groupByMasteryLevel()
        
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    label: "Learning",
                    value: "\(masteryLevels[0])",
                    color: Color(red: 1.0, green: 0.6, blue: 0.0),
                    icon: "star"
                )
                
                StatCard(
                    label: "Familiar",
                    value: "\(masteryLevels[1])",
                    color: Color(red: 1.0, green: 0.84, blue: 0.0),
                    icon: "pencil"
                )
            }
            
            HStack(spacing: 12) {
                StatCard(
                    label: "Competent",
                    value: "\(masteryLevels[2])",
                    color: Color(red: 0.4, green: 0.8, blue: 0.2),
                    icon: "checkmark.circle"
                )
                
                StatCard(
                    label: "Mastered",
                    value: "\(masteryLevels[3])",
                    color: Color(red: 0.2, green: 0.8, blue: 0.4),
                    icon: "crown"
                )
            }
        }
    }
    
    // MARK: - Content Section
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Study Cards")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.black)
                
                Spacer()
                
                if !studyItems.isEmpty {
                    Text("\(studyItems.count) cards")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                }
            }
            
            if studyItems.isEmpty {
                EmptyCardListView {
                    Task { await regenerateFlashcards() }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(studyItems) { card in
                        FlashcardRow(
                            card: card,
                            onExplain: {
                                showingExplainSheet = card
                                vibrate()
                            }
                        )
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await regenerateFlashcards() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Regenerate Flashcards")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.8, blue: 0.4),
                            Color(red: 0.0, green: 0.7, blue: 0.3)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isRegenerating)
            .opacity(isRegenerating ? 0.6 : 1.0)
        }
    }
    
    // MARK: - Error Banner
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
            
            Text(message)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(Color(red: 0.7, green: 0.0, blue: 0.0))
            
            Spacer()
        }
        .padding(14)
        .background(Color(red: 1.0, green: 0.9, blue: 0.9))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Stat Card Component
    private struct StatCard: View {
        let label: String
        let value: String
        let color: Color
        let icon: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundColor(.gray)
                        
                        Text(value)
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundColor(color)
                    }
                    
                    Spacer()
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(color.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(0.08))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Flashcard Row
    private struct FlashcardRow: View {
        var card: StudyItem
        let onExplain: () -> Void
        @State private var isFlipped = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isFlipped ? "Answer" : "Question")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                            .textCase(.uppercase)
                        
                        Text(isFlipped ? card.answer : card.question)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(.black)
                            .lineLimit(3)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isFlipped.toggle()
                        }
                    } label: {
                        Image(systemName: isFlipped ? "eye.slash" : "eye")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                            .frame(width: 40, height: 40)
                    }
                }
                
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(Color(red: 0.2, green: 0.8, blue: 0.4))
                            .frame(width: CGFloat(card.mastery) * 2.4, height: 6)
                    }
                    
                    Text("\(card.mastery)%")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(.gray)
                        .frame(minWidth: 35)
                }
                
                Button {
                    onExplain()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14, weight: .regular))
                        
                        Text("Deep Explain")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.0))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
    }
    
    // MARK: - Empty State
    private struct EmptyCardListView: View {
        let regenerate: () -> Void
        
        var body: some View {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.97, blue: 0.95))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                
                VStack(spacing: 8) {
                    Text("No flashcards yet")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.black)
                    
                    Text("Generate flashcards to start your study journey")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                Button {
                    regenerate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Generate Flashcards")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.2, green: 0.8, blue: 0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
    }
    
    // MARK: - Explanation Sheet
    private struct ExplanationSheet: View {
        let studyItem: StudyItem
        @State private var loading = true
        @State private var explanation: String = ""
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationView {
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.98, green: 0.97, blue: 0.95),
                            Color.white
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if loading {
                                    VStack(spacing: 16) {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                            .tint(Color(red: 0.2, green: 0.8, blue: 0.4))
                                        
                                        Text("Generating explanation...")
                                            .font(.system(size: 14, weight: .regular, design: .default))
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    .padding(40)
                                } else {
                                    Text(explanation)
                                        .font(.system(size: 15, weight: .regular, design: .default))
                                        .foregroundColor(.black)
                                        .lineSpacing(1.5)
                                }
                            }
                            .padding(20)
                        }
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.2, green: 0.8, blue: 0.4))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(20)
                    }
                }
                .navigationTitle("Deep Explanation")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await explain()
                }
            }
        }
        
        private func explain() async {
            loading = true
            defer { loading = false }
            do {
                let result = try await GroqAPI.shared.deepExplain(for: studyItem)
                self.explanation = result
            } catch {
                explanation = "Sorry, I couldn't generate an explanation. Please try again."
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func dateString(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }
    
    private func groupByMasteryLevel() -> [Int] {
        let learning = studyItems.filter { $0.mastery < 20 }.count
        let familiar = studyItems.filter { $0.mastery >= 20 && $0.mastery < 50 }.count
        let competent = studyItems.filter { $0.mastery >= 50 && $0.mastery < 80 }.count
        let mastered = studyItems.filter { $0.mastery >= 80 }.count
        return [learning, familiar, competent, mastered]
    }
    
    private func sourceTypeIcon(_ type: SourceType) -> Image {
        switch type {
        case .pdf:
            return Image(systemName: "doc.fill")
        case .text:
            return Image(systemName: "doc.text.fill")
        case .image:
            return Image(systemName: "photo.fill")
        case .audio:
            return Image(systemName: "waveform.circle.fill")
        case .url:
            return Image(systemName: "link.circle.fill")
        case .file:
            return Image(systemName: "folder.fill")
        }
    }
    
    private func regenerateFlashcards() async {
        isRegenerating = true
        errorMessage = nil
        vibrate()
        
        do {
            try await StudyGenerator.shared.generateFlashcards(for: document)
        } catch {
            errorMessage = "Failed to regenerate flashcards. Please try again."
        }
        
        isRegenerating = false
    }
    
    private func vibrate() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
