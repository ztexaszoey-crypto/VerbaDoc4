import PhotosUI
import SwiftUI

struct TutorView: View {
    let item: StudyItem
    var startsWithDeepExplain: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var hintLevel = 0
    @State private var messages: [TutorMessage] = []
    @State private var showFullAnswer = false
    @State private var composer = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessingPhoto = false

    private let maxHints = 3
    private let maxOCRPreviewLength = 600

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            questionCard

                            if startsWithDeepExplain {
                                deepExplainCard
                            }

                            ForEach(messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if messages.isEmpty {
                                tutorIntroCard
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()
                composerBar
                    .padding()
            }
            .navigationTitle("Verba Tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if startsWithDeepExplain {
                    revealAnswer()
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await handlePhoto(newValue) }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "face.smiling.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(VerbaTheme.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ask for hints, examples, or homework help")
                    .font(.subheadline.bold())
                Text("Verba keeps the context from this flashcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Question", systemImage: "questionmark.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(item.question)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .solidCard()
    }

    private var deepExplainCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Deep Explain", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(VerbaTheme.green)
            Text(item.answer)
                .font(.headline)
                .foregroundStyle(VerbaTheme.green)
            Text(item.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Text(exampleText)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .solidCard(VerbaTheme.cream)
    }

    private var tutorIntroCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "face.smiling.fill")
                .font(.system(size: 28))
                .foregroundStyle(VerbaTheme.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hi! I'm here to help.")
                    .font(.subheadline.bold())
                Text("Use hints, ask a question, or upload a homework photo for OCR-based help.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .solidCard()
    }

    @ViewBuilder
    private func messageBubble(_ message: TutorMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .tutor {
                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(VerbaTheme.green)
            } else {
                Spacer()
            }

            Text(message.content)
                .font(.subheadline)
                .padding(10)
                .background(message.role == .tutor ? Color(.secondarySystemBackground) : VerbaTheme.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, alignment: message.role == .tutor ? .leading : .trailing)

            if message.role == .student {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var composerBar: some View {
        VStack(spacing: 12) {
            if showFullAnswer {
                deepExplainCard
            }

            HStack(spacing: 12) {
                Button {
                    requestHint()
                } label: {
                    Label("Hint", systemImage: "lightbulb")
                }
                .buttonStyle(VerbaSecondaryButtonStyle())
                .disabled(hintLevel >= maxHints)

                Button {
                    revealAnswer()
                } label: {
                    Label("Deep Explain", systemImage: "sparkles")
                }
                .buttonStyle(VerbaButtonStyle())
            }

            HStack(spacing: 10) {
                TextField("Ask Verba anything about this card…", text: $composer)
                    .textFieldStyle(.roundedBorder)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: isProcessingPhoto ? "hourglass" : "camera.fill")
                        .foregroundStyle(VerbaTheme.green)
                }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(VerbaTheme.green)
                }
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var exampleText: String {
        let prompt = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Example: Imagine explaining “\(prompt)” to a friend. Start with the definition, connect it to \(item.documentTitle ?? "your notes"), then test yourself with one real-world example."
    }

    private func requestHint() {
        HapticManager.impact()
        hintLevel += 1

        let hint: String
        switch hintLevel {
        case 1:
            let words = item.answer.split(separator: " ")
            let firstLetter = words.first.map { String($0.prefix(1)) + "..." } ?? "..."
            hint = "Start with this clue: \(firstLetter)"
        case 2:
            let answer = item.answer
            let half = answer.prefix(max(1, answer.count / 2))
            hint = "Next clue: \(half)…"
        case 3:
            hint = "Context clue: \(item.explanation)"
        default:
            hint = "You've used all your hints."
        }

        messages.append(TutorMessage(role: .student, content: "Can I get a hint?"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            messages.append(TutorMessage(role: .tutor, content: hint))
        }
    }

    private func revealAnswer() {
        HapticManager.success()
        withAnimation { showFullAnswer = true }
        messages.append(TutorMessage(role: .student, content: "Deep explain this with examples."))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            messages.append(TutorMessage(role: .tutor, content: "Absolutely — I broke the answer down below and added an example angle for you."))
        }
    }

    private func sendMessage() {
        let prompt = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        messages.append(TutorMessage(role: .student, content: prompt))
        composer = ""

        let response = contextualReply(for: prompt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            messages.append(TutorMessage(role: .tutor, content: response))
        }
    }

    private func contextualReply(for prompt: String) -> String {
        let lowercased = prompt.lowercased()
        if lowercased.contains("example") {
            return exampleText
        }
        if lowercased.contains("why") {
            return "Because the key idea is \(item.answer). The flashcard’s explanation points back to: \(item.explanation)"
        }
        if lowercased.contains("step") || lowercased.contains("how") {
            return "Try this sequence: 1) define \(item.answer), 2) connect it to the note context, 3) test yourself with a new example."
        }
        return "Here’s the core takeaway: \(item.answer). Use the explanation below to anchor it in context, then practice saying it in your own words."
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw DocumentImportError.unreadableImage
            }
            let extracted = try await DocumentImportService.extractText(from: data)
            let preview = truncatedOCRPreview(extracted)
            messages.append(TutorMessage(role: .student, content: "Can you help with this homework photo?"))
            messages.append(TutorMessage(role: .tutor, content: "I extracted this text:\n\n\(preview)\n\nHere’s the connection: compare it to \(itemAnswerSummary)."))
        } catch {
            messages.append(TutorMessage(role: .tutor, content: error.localizedDescription))
        }
        isProcessingPhoto = false
    }

    private var itemAnswerSummary: String {
        "\(item.answer) — \(item.explanation)"
    }

    private func truncatedOCRPreview(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxOCRPreviewLength))
    }
}
