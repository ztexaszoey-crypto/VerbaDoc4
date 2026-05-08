import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AddMaterialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("groq.apiKey") private var groqAPIKey = ""

    @State private var title = ""
    @State private var extractedText = ""
    @State private var sourceType: SourceType = .text
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPDFImporter = false
    @State private var isBusy = false
    @State private var statusMessage = ""
    @State private var errorMessage: String?

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
                    .pickerStyle(.segmented)
                }

                Section(sourceType.displayName) {
                    sourceControls
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Extracted text") {
                    TextEditor(text: $extractedText)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle("Add Material")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isBusy ? "Generating…" : "Save") {
                        Task { await saveDocument() }
                    }
                    .disabled(isBusy || extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                handlePDFImport(result)
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await extractTextFromPhoto(newValue) }
            }
        }
    }

    @ViewBuilder
    private var sourceControls: some View {
        switch sourceType {
        case .text:
            Text("Paste or type notes directly. AI flashcards will be generated when you save.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .pdf:
            Button {
                showPDFImporter = true
            } label: {
                Label("Upload PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(VerbaButtonStyle())
        case .photoOCR:
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Upload Photo", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VerbaButtonStyle())
        }
    }

    private func handlePDFImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            isBusy = true
            errorMessage = nil
            extractedText = try DocumentImportService.extractText(fromPDFAt: url)
            statusMessage = "Imported \(url.lastPathComponent)"
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func extractTextFromPhoto(_ item: PhotosPickerItem) async {
        isBusy = true
        errorMessage = nil
        statusMessage = "Running OCR…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw DocumentImportError.unreadableImage
            }
            extractedText = try await DocumentImportService.extractText(from: data)
            statusMessage = "Photo text extracted successfully."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = ""
        }
        isBusy = false
    }

    @MainActor
    private func saveDocument() async {
        isBusy = true
        errorMessage = nil
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = Document(
            title: cleanedTitle.isEmpty ? "Untitled" : cleanedTitle,
            extractedText: extractedText,
            sourceType: sourceType
        )
        modelContext.insert(document)

        let cards = await FlashcardGenerationService.generateCards(
            from: extractedText,
            documentTitle: document.title,
            groqAPIKey: groqAPIKey
        )

        for card in cards {
            modelContext.insert(card)
            document.studyItems?.append(card)
        }

        try? modelContext.save()
        isBusy = false
        dismiss()
    }
}
