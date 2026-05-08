import SwiftData
import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("groq.apiKey") private var groqAPIKey = ""

    @Bindable var document: Document

    @State private var selectedItem: StudyItem?
    @State private var isGenerating = false

    private var items: [StudyItem] { document.studyItems ?? [] }

    var body: some View {
        List {
            Section("Overview") {
                HStack {
                    Label(document.sourceType.displayName, systemImage: document.sourceType.systemIcon)
                    Spacer()
                    Text("\(StudyEngine.mastery(for: document))% mastery")
                        .foregroundStyle(VerbaTheme.green)
                        .fontWeight(.semibold)
                }

                HStack {
                    Label("Created", systemImage: "calendar")
                    Spacer()
                    Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Source Text") {
                Text(document.extractedText.isEmpty ? "No extracted text" : document.extractedText)
                    .font(.body)
            }

            Section("Study Cards") {
                if items.isEmpty {
                    Text("No cards generated yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.question)
                                .font(.headline)
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("\(StudyEngine.mastery(for: item))% mastery")
                                    .font(.caption)
                                    .foregroundStyle(VerbaTheme.green)
                                Spacer()
                                Button("Deep Explain") {
                                    selectedItem = item
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            if !StudyEngine.weakTopics(from: items).isEmpty {
                Section("Weak Topics") {
                    ForEach(StudyEngine.weakTopics(from: items).prefix(3)) { topic in
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
        }
        .navigationTitle(document.title.isEmpty ? "Untitled" : document.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    TodayPracticeView(items: items, sessionTitle: document.title.isEmpty ? "Document Practice" : document.title)
                } label: {
                    Image(systemName: "play.fill")
                }
                Button(isGenerating ? "…" : "Regenerate") {
                    Task { await generateCards() }
                }
                .disabled(isGenerating || document.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(item: $selectedItem) { item in
            TutorView(item: item, startsWithDeepExplain: true)
        }
    }

    @MainActor
    private func generateCards() async {
        isGenerating = true
        let generated = await FlashcardGenerationService.generateCards(
            from: document.extractedText,
            documentTitle: document.title,
            groqAPIKey: groqAPIKey
        )
        guard !generated.isEmpty else {
            isGenerating = false
            return
        }

        var existingQuestions = Set(items.map { $0.question.lowercased() })
        for item in generated {
            let key = item.question.lowercased()
            guard !existingQuestions.contains(key) else { continue }
            modelContext.insert(item)
            document.studyItems?.append(item)
            existingQuestions.insert(key)
        }
        try? modelContext.save()
        isGenerating = false
    }
}
