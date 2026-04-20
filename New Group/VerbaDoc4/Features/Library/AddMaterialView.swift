import SwiftUI
import SwiftData

struct AddMaterialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var extractedText = ""
    @State private var sourceType: SourceType = .text

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    TextField("Title", text: $title)
                    Picker("Source", selection: $sourceType) {
                        ForEach(SourceType.allCases, id: \.self) { source in
                            Label(source.displayName, systemImage: source.systemIcon)
                                .tag(source)
                        }
                    }
                }

                Section("Text") {
                    TextEditor(text: $extractedText)
                        .frame(minHeight: 180)
                }
            }
            .navigationTitle("Add Material")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDocument()
                    }
                    .disabled(extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveDocument() {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = Document(
            title: cleanedTitle.isEmpty ? "Untitled" : cleanedTitle,
            extractedText: extractedText,
            sourceType: sourceType
        )
        modelContext.insert(document)

        let cards = StudyGenerator.generateCards(from: extractedText, documentTitle: document.title, maxCards: 12)
        for card in cards {
            modelContext.insert(card)
            document.studyItems?.append(card)
        }

        dismiss()
    }
}
