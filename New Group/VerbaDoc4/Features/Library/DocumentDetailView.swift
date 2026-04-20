import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var document: Document

    var body: some View {
        List {
            Section("Text") {
                Text(document.extractedText.isEmpty ? "No extracted text" : document.extractedText)
                    .font(.body)
            }

            Section("Study Cards") {
                let items = document.studyItems ?? []
                if items.isEmpty {
                    Text("No cards generated yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.question)
                                .font(.headline)
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(document.title.isEmpty ? "Untitled" : document.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Generate") {
                    generateCards()
                }
                .disabled(document.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func generateCards() {
        let generated = StudyGenerator.generateCards(from: document.extractedText, documentTitle: document.title, maxCards: 20)
        guard !generated.isEmpty else { return }

        var existing = Set((document.studyItems ?? []).map { $0.question.lowercased() })
        for item in generated {
            let key = item.question.lowercased()
            guard !existing.contains(key) else { continue }
            modelContext.insert(item)
            document.studyItems?.append(item)
            existing.insert(key)
        }
    }
}
