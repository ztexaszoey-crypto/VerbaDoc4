import SwiftUI
import SwiftData

struct AddMaterialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var text = ""

    private let generator = StudyGenerator()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Paste text", text: $text, axis: .vertical)
                    .lineLimit(5...10)
            }
            .navigationTitle("Add Material")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveMaterial() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveMaterial() {
        let document = Document(title: title.isEmpty ? "Untitled" : title, extractedText: text)
        modelContext.insert(document)

        let generated = generator.generateItems(from: text, documentTitle: document.title)
        for item in generated {
            document.studyItems?.append(item)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AddMaterialView()
}
