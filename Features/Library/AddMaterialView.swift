import SwiftUI
import SwiftData
import PhotosUI

struct AddMaterialView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var generator = StudyGenerator()

    enum Mode: String, CaseIterable {
        case pdf = "PDF", photo = "Photo", text = "Text"
        var icon: String {
            switch self {
            case .pdf:   return "doc.richtext"
            case .photo: return "camera.viewfinder"
            case .text:  return "square.and.pencil"
            }
        }
    }

    @State private var mode: Mode = .pdf
    @State private var title = ""
    @State private var pastedText = ""
    @State private var extractedText = ""
    @State private var showFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isExtracting = false
    @State private var extractError: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    modePicker
                    titleField
                    inputPanel
                    if !extractedText.isEmpty { previewCard }
                    if let e = extractError { errorCard(e) }
                    generateButton
                }
                .padding(20)
            }
            .background(VerbaTheme.background.ignoresSafeArea())
            .navigationTitle("Add Material")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .alert("Flashcards Ready", isPresented: $showSuccess) {
                Button("Let's go") { dismiss() }
            } message: {
                Text(generator.progress)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    mode = m
                    extractedText = ""
                    extractError = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                        Text(m.rawValue).fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(mode == m ? VerbaTheme.green : Color.clear)
                    .foregroundStyle(mode == m ? .white : VerbaTheme.muted)
                }
            }
        }
        .background(VerbaTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title").font(.caption.bold()).foregroundStyle(VerbaTheme.muted)
            TextField("e.g. Biology Chapter 7", text: $title)
                .padding(12)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VerbaTheme.ink.opacity(0.12), lineWidth: 1.5)
                )
        }
    }

    @ViewBuilder
    private var inputPanel: some View {
        switch mode {
        case .pdf:
            Button { showFilePicker = true } label: {
                uploadBox(icon: "doc.richtext", label: "Tap to choose a PDF", sub: "Textbooks, lecture slides, notes")
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { r in
                Task { await handlePDF(r) }
            }
        case .photo:
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                uploadBox(icon: "photo.on.rectangle.angled", label: "Choose from Photos", sub: "Handwritten notes, textbook pages")
            }
        case .text:
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste your notes").font(.caption.bold()).foregroundStyle(VerbaTheme.muted)
                TextEditor(text: $pastedText)
                    .frame(minHeight: 180)
                    .padding(12)
                    .background(VerbaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(VerbaTheme.ink.opacity(0.12), lineWidth: 1.5)
                    )
                    .onChange(of: pastedText) { _, v in extractedText = v }
            }
        }
    }

    private func uploadBox(icon: String, label: String, sub: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36, weight: .semibold)).foregroundStyle(VerbaTheme.green)
            Text(label).font(.subheadline.bold())
            Text(sub).font(.caption).foregroundStyle(VerbaTheme.muted)
            if isExtracting { ProgressView().tint(VerbaTheme.green) }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(VerbaTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(VerbaTheme.green.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(VerbaTheme.green)
                Text("Text extracted").font(.caption.bold()).foregroundStyle(VerbaTheme.green)
                Spacer()
                Text("\(extractedText.count) chars").font(.caption2).foregroundStyle(VerbaTheme.muted)
            }
            Text(String(extractedText.prefix(300)) + (extractedText.count > 300 ? "..." : ""))
                .font(.caption).foregroundStyle(VerbaTheme.muted).lineLimit(4)
        }
        .padding(14)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorCard(_ msg: String) -> some View {
        Text(msg).font(.caption).foregroundStyle(.red)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 10) {
                if generator.isGenerating || isExtracting {
                    ProgressView().tint(.white).scaleEffect(0.85)
                }
                Text(generator.isGenerating ? generator.progress : isExtracting ? "Extracting..." : "Generate Flashcards")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(VerbaButtonStyle())
        .disabled(
            title.trimmingCharacters(in: .whitespaces).isEmpty ||
            extractedText.trimmingCharacters(in: .whitespaces).isEmpty ||
            generator.isGenerating || isExtracting
        )
    }

    private func handlePDF(_ result: Result<[URL], Error>) async {
        isExtracting = true
        extractError = nil
        do {
            guard let url = try result.get().first else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let text = PDFExtractor.extractText(from: url)
            if text.isEmpty {
                extractError = "No text found in this PDF. Try the Photo tab instead."
            } else {
                extractedText = text
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            }
        } catch {
            extractError = "Could not open PDF: \(error.localizedDescription)"
        }
        isExtracting = false
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isExtracting = true
        extractError = nil
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            let text = await OCRExtractor.extractText(from: img)
            if text.isEmpty {
                extractError = "Could not read text. Make sure the image is clear and well-lit."
            } else {
                extractedText = text
            }
        } else {
            extractError = "Could not load photo."
        }
        isExtracting = false
    }

    private func generate() async {
        let t = title.trimmingCharacters(in: .whitespaces)
        let text = extractedText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !text.isEmpty else { return }
        let src: SourceType = mode == .pdf ? .pdf : mode == .photo ? .photoOCR : .text
        let doc = Document(title: t, extractedText: text, sourceType: src)
        modelContext.insert(doc)
        await generator.generateFlashcards(for: doc, context: modelContext)
        if generator.errorMessage == nil { showSuccess = true }
    }
}
