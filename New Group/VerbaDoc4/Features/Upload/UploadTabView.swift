import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - UploadTabView
//
// Fast, intelligent, zero friction.
// Flow: input → type picker → processing → success
// The type picker is what makes this feel like a specialized tutor, not a file converter.

// MARK: - Study Generation Type

enum StudyGenType: String, CaseIterable {
    case flashcards   = "Flashcards"
    case quickQuiz    = "Quick Quiz"
    case practiceExam = "Practice Exam"
    case studyGuide   = "Study Guide"
    case teachMe      = "Teach Me"
    case keyConcepts  = "Key Concepts"

    var icon: String {
        switch self {
        case .flashcards:   return "rectangle.on.rectangle"
        case .quickQuiz:    return "checkmark.circle"
        case .practiceExam: return "doc.text.magnifyingglass"
        case .studyGuide:   return "list.bullet.rectangle"
        case .teachMe:      return "person.wave.2"
        case .keyConcepts:  return "sparkles"
        }
    }

    var tagline: String {
        switch self {
        case .flashcards:   return "active recall"
        case .quickQuiz:    return "test yourself"
        case .practiceExam: return "exam simulation"
        case .studyGuide:   return "structured overview"
        case .teachMe:      return "concept by concept"
        case .keyConcepts:  return "must-know terms"
        }
    }

    var color: Color {
        switch self {
        case .flashcards:   return VerbaTheme.green
        case .quickQuiz:    return VerbaTheme.blue
        case .practiceExam: return VerbaTheme.orange
        case .studyGuide:   return VerbaTheme.brown
        case .teachMe:      return Color(red: 0.55, green: 0.20, blue: 0.80)
        case .keyConcepts:  return VerbaTheme.darkGreen
        }
    }
}

struct UploadTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var tabRouter: TabRouter

    enum Step { case input, typePicker, processing, reviewing, success }

    @State private var step: Step = .input
    @State private var mode: InputMode = .pdf
    @State private var selectedGenType: StudyGenType = .flashcards
    @State private var title = ""
    @State private var pastedText = ""
    @State private var extractedText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showFilePicker = false
    @State private var isExtracting = false
    @State private var extractError: String?
    @State private var createdCardCount = 0
    @State private var createdDocument: Document?
    @State private var showExam = false
    @State private var showStudyNow = false
    @State private var pendingCards: [EditableCard] = []
    @State private var isGenerating = false   // guards against double-tap creating duplicate docs
    // Deck import
    @State private var showDeckImporter  = false
    @State private var deckImportError: String? = nil
    @State private var deckImportSuccess = false

    enum InputMode: String, CaseIterable {
        case pdf = "PDF", photo = "Photo", text = "Text"
        var icon: String {
            switch self {
            case .pdf:   return "doc.richtext"
            case .photo: return "photo"
            case .text:  return "text.alignleft"
            }
        }
    }

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            switch step {
            case .input:
                inputView
                    .transition(.opacity)
            case .typePicker:
                typePickerView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            case .processing:
                GeneratingView(genType: selectedGenType)
                    .transition(.opacity)
            case .reviewing:
                GenerationReviewView(
                    initialCards: pendingCards,
                    genType: selectedGenType,
                    onApprove: { cards in
                        Task { await commitReviewedCards(cards) }
                    },
                    onCancel: {
                        withAnimation(.verba) { step = .input }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            case .success:
                successView
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity
                    ))
            }
        }
        .animation(.verba, value: step)
        .sheet(isPresented: $showExam) {
            if let doc = createdDocument {
                ExamView(preselectedDocument: doc)
            }
        }
        .fullScreenCover(isPresented: $showStudyNow) {
            if let doc = createdDocument {
                FlashcardStudyView(document: doc, scope: .all)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    // MARK: - Type Picker View
    // The key differentiator — makes VerbaDoc feel like a specialized tutor.

    private var typePickerView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.verba) { step = .input }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .medium))
                            Text("back")
                                .font(VerbaFont.syne(.regular, size: 13))
                        }
                        .foregroundStyle(VerbaTheme.muted)
                    }
                    .padding(.bottom, 4)

                    Text("what do you need?")
                        .font(VerbaFont.serif(size: 28))
                        .foregroundStyle(VerbaTheme.ink)
                    Text("we'll build exactly that from your notes.")
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // 2-column grid of type tiles
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(StudyGenType.allCases, id: \.self) { genType in
                        typeCard(genType)
                    }
                }
                .padding(.horizontal, 20)

                // Generate CTA
                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedGenType.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text("build my \(selectedGenType.rawValue.lowercased())")
                            .font(VerbaFont.syne(.medium, size: 15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(selectedGenType.color)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 60)
            }
        }
    }

    private func typeCard(_ genType: StudyGenType) -> some View {
        Button {
            HapticManager.selection()
            withAnimation(.verbaSnappy) { selectedGenType = genType }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(genType.color.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: genType.icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(genType.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(genType.rawValue)
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(VerbaTheme.ink)
                    Text(genType.tagline)
                        .font(VerbaFont.syne(.regular, size: 11))
                        .foregroundStyle(VerbaTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(selectedGenType == genType ? genType.color.opacity(0.07) : VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(selectedGenType == genType ? genType.color.opacity(0.35) : VerbaTheme.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input View

    private var inputView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("drop in your notes.")
                        .font(VerbaFont.serif(size: 28))
                        .foregroundStyle(VerbaTheme.ink)
                    Text("we'll build your study plan.")
                        .font(VerbaFont.syne(.regular, size: 15))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Mode picker
                modePicker
                    .padding(.horizontal, 20)

                // Title field
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("set title")
                    HStack(spacing: 10) {
                        Image(systemName: "textformat")
                            .font(.system(size: 14))
                            .foregroundStyle(VerbaTheme.muted)
                        TextField("e.g. bio chapter 7, calc midterm", text: $title)
                            .font(VerbaFont.syne(.regular, size: 15))
                            .foregroundStyle(VerbaTheme.ink)
                            .tint(VerbaTheme.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(VerbaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                            .stroke(VerbaTheme.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)

                // Content input
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("content")
                    contentInput
                }
                .padding(.horizontal, 20)

                // Error
                if let err = extractError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 13))
                        Text(err)
                            .font(VerbaFont.syne(.regular, size: 13))
                    }
                    .foregroundStyle(VerbaTheme.danger)
                    .padding(.horizontal, 20)
                }

                // Extracted preview
                if !extractedText.isEmpty && mode != .text {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("preview")
                        Text(String(extractedText.prefix(180)) + (extractedText.count > 180 ? "…" : ""))
                            .font(VerbaFont.syne(.regular, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                            .lineSpacing(3)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(VerbaTheme.cream.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                    .stroke(VerbaTheme.border, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                }

                // Next: go to type picker
                Button {
                    HapticManager.selection()
                    withAnimation(.verba) { step = .typePicker }
                } label: {
                    HStack(spacing: 8) {
                        if isExtracting {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(.white)
                        } else {
                            Text("choose what to build  →")
                                .font(VerbaFont.syne(.medium, size: 15))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canGenerate ? VerbaTheme.green : VerbaTheme.muted.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                }
                .disabled(!canGenerate)
                .padding(.horizontal, 20)
                .animation(.verba, value: canGenerate)

                // ── Import a shared deck ──────────────────────────────────
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(VerbaTheme.border)
                            .frame(height: 1)
                        Text("or")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.muted)
                        Rectangle()
                            .fill(VerbaTheme.border)
                            .frame(height: 1)
                    }

                    Button {
                        deckImportError  = nil
                        deckImportSuccess = false
                        showDeckImporter  = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                            Text("import a shared deck")
                                .font(VerbaFont.syne(.medium, size: 14))
                        }
                        .foregroundStyle(VerbaTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(VerbaTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                                .stroke(VerbaTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if let err = deckImportError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 12))
                            Text(err)
                                .font(VerbaFont.syne(.regular, size: 12))
                        }
                        .foregroundStyle(VerbaTheme.danger)
                    }

                    if deckImportSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("deck imported — find it in your library.")
                                .font(VerbaFont.syne(.regular, size: 12))
                        }
                        .foregroundStyle(VerbaTheme.green)
                    }
                }
                .padding(.horizontal, 20)
                .fileImporter(
                    isPresented: $showDeckImporter,
                    allowedContentTypes: [.json, UTType(filenameExtension: "verbadeck") ?? .data],
                    allowsMultipleSelection: false
                ) { result in
                    Task { await handleDeckImport(result) }
                }

                Spacer(minLength: 80)
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(InputMode.allCases, id: \.self) { m in
                Button {
                    HapticManager.selection()
                    withAnimation(.verbaSnappy) { mode = m }
                    extractedText = ""
                    extractError = nil
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: m.icon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(mode == m ? VerbaTheme.green : VerbaTheme.muted)
                        Text(m.rawValue.lowercased())
                            .font(VerbaFont.syne(.medium, size: 12))
                            .foregroundStyle(mode == m ? VerbaTheme.ink : VerbaTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(mode == m ? VerbaTheme.green.opacity(0.08) : VerbaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                            .stroke(mode == m ? VerbaTheme.green.opacity(0.30) : VerbaTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Content Input

    @ViewBuilder
    private var contentInput: some View {
        switch mode {
        case .pdf:
            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                            .fill(extractedText.isEmpty ? VerbaTheme.cream : VerbaTheme.green.opacity(0.10))
                            .frame(width: 40, height: 40)
                        Image(systemName: extractedText.isEmpty ? "doc.richtext" : "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(extractedText.isEmpty ? VerbaTheme.brown : VerbaTheme.green)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(extractedText.isEmpty ? "choose a PDF" : "PDF loaded")
                            .font(VerbaFont.syne(.medium, size: 14))
                            .foregroundStyle(extractedText.isEmpty ? VerbaTheme.ink : VerbaTheme.green)
                        Text(extractedText.isEmpty ? "tap to browse files" : "\(extractedText.count) characters extracted")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .padding(14)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .stroke(extractedText.isEmpty ? VerbaTheme.border : VerbaTheme.green.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                Task { await handlePDF(result) }
            }

        case .photo:
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                            .fill(extractedText.isEmpty ? VerbaTheme.cream : VerbaTheme.green.opacity(0.10))
                            .frame(width: 40, height: 40)
                        Image(systemName: extractedText.isEmpty ? "photo" : "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(extractedText.isEmpty ? VerbaTheme.brown : VerbaTheme.green)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isExtracting ? "reading text…" : extractedText.isEmpty ? "choose a photo" : "photo loaded")
                            .font(VerbaFont.syne(.medium, size: 14))
                            .foregroundStyle(isExtracting ? VerbaTheme.muted : extractedText.isEmpty ? VerbaTheme.ink : VerbaTheme.green)
                        Text(isExtracting ? "this takes a sec" : extractedText.isEmpty ? "lecture slides, whiteboard, handwritten notes" : "\(extractedText.count) characters extracted")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(VerbaTheme.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                }
                .padding(14)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                        .stroke(extractedText.isEmpty ? VerbaTheme.border : VerbaTheme.green.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

        case .text:
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.ink)
                    .tint(VerbaTheme.green)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .onChange(of: pastedText) { _, v in extractedText = v }

                if pastedText.isEmpty {
                    Text("paste your notes here…")
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.muted.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Mascot celebrates
                VerbaMascot(mood: .cheering, size: 88)

                VStack(spacing: 8) {
                    Text("\(createdCardCount) \(successItemLabel), ready to go.")
                        .font(VerbaFont.serif(size: 26))
                        .foregroundStyle(VerbaTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(title)
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                // Stats strip
                HStack(spacing: 0) {
                    successStat("\(createdCardCount)", label: successItemLabel, color: VerbaTheme.green)
                    Rectangle()
                        .fill(VerbaTheme.border)
                        .frame(width: 1, height: 32)
                    successStat(selectedGenType.rawValue.lowercased(), label: "type", color: selectedGenType.color)
                    Rectangle()
                        .fill(VerbaTheme.border)
                        .frame(width: 1, height: 32)

                    // XP pill as stat
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                            Text("+\(XPSystem.xpForAction(.summarizeDocument))")
                                .font(VerbaFont.syne(.bold, size: 18))
                        }
                        .foregroundStyle(VerbaTheme.yellow)
                        Text("xp earned")
                            .font(VerbaFont.syne(.regular, size: 11))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                        .stroke(VerbaTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button(successCTA) {
                    if selectedGenType == .quickQuiz || selectedGenType == .practiceExam {
                        showExam = true
                    } else if selectedGenType == .flashcards {
                        showStudyNow = true
                    } else {
                        tabRouter.selected = .library
                    }
                }
                .primaryButtonStyle()

                Button("add another set") { resetState() }
                    .outlineButtonStyle(color: VerbaTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .verbaBackground()
    }

    private func successStat(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VerbaFont.syne(.bold, size: 20))
                .foregroundStyle(color)
            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var successItemLabel: String {
        switch selectedGenType {
        case .flashcards:               return createdCardCount == 1 ? "card"     : "cards"
        case .quickQuiz:                return createdCardCount == 1 ? "question" : "questions"
        case .practiceExam:             return createdCardCount == 1 ? "question" : "questions"
        case .studyGuide:               return createdCardCount == 1 ? "section"  : "sections"
        case .teachMe:                  return createdCardCount == 1 ? "concept"  : "concepts"
        case .keyConcepts:              return createdCardCount == 1 ? "term"     : "terms"
        }
    }

    private var successCTA: String {
        switch selectedGenType {
        case .quickQuiz, .practiceExam: return "start the exam"
        case .flashcards:               return "start drilling"
        case .studyGuide:               return "view my guide"
        case .teachMe:                  return "start learning"
        case .keyConcepts:              return "review concepts"
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(VerbaFont.syne(.semibold, size: 11))
            .foregroundStyle(VerbaTheme.muted)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private var canGenerate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !extractedText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isExtracting
    }

    // MARK: - Logic

    private func generate() async {
        guard !isGenerating else { return }
        let t    = title.trimmingCharacters(in: .whitespaces)
        let text = extractedText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !text.isEmpty else { return }

        isGenerating = true
        extractError = nil   // clear stale error from any prior attempt
        withAnimation(.verba) { step = .processing }

        do {
            let cards = try await StudyGenerator.shared.generateForReview(content: text, genType: selectedGenType)
            pendingCards = cards
            withAnimation(.verba) { step = .reviewing }
        } catch let groqError as GroqAPIError {
            // Surface a human-friendly message for known API errors
            switch groqError {
            case .missingAPIKey:     extractError = "No API key configured. Add one in Settings."
            case .httpError(429, _): extractError = "AI is busy right now. Wait a moment and try again."
            case .networkError:      extractError = "No internet connection. Check your network and try again."
            default:                 extractError = "Couldn't reach AI. Try again."
            }
            withAnimation(.verba) { step = .input }
        } catch {
            extractError = StudyGenerator.shared.errorMessage ?? "Generation failed. Check your connection and try again."
            withAnimation(.verba) { step = .input }
        }

        isGenerating = false
    }

    /// Called when the user approves their reviewed cards.
    /// Creates the Document and commits cards to SwiftData.
    /// Guard prevents double-call if onApprove fires twice (rapid taps).
    private func commitReviewedCards(_ cards: [EditableCard]) async {
        guard step == .reviewing else { return }   // only valid from review step
        let t    = title.trimmingCharacters(in: .whitespaces)
        let text = extractedText.trimmingCharacters(in: .whitespaces)
        let src: SourceType = mode == .pdf ? .pdf : mode == .photo ? .photoOCR : .text
        let doc = Document(title: t, content: text, sourceType: src)
        modelContext.insert(doc)

        StudyGenerator.shared.commitCards(cards, to: doc, context: modelContext)

        createdCardCount = doc.studyItems.count
        createdDocument  = doc
        xpManager.award(.summarizeDocument)
        HapticManager.success()

        withAnimation(.verba) { step = .success }

        // Route non-flashcard types directly to the right experience.
        if selectedGenType == .quickQuiz || selectedGenType == .practiceExam {
            let capturedDoc = createdDocument
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if step == .success && createdDocument?.id == capturedDoc?.id {
                    showExam = true
                }
            }
        }
    }

    private func handlePDF(_ result: Result<[URL], Error>) async {
        isExtracting = true
        extractError = nil
        do {
            guard let url = try result.get().first else { return }
            let ok = url.startAccessingSecurityScopedResource()
            // Offload synchronous PDF extraction to a background thread so the
            // MainActor is never blocked — large PDFs can take 1-3 seconds.
            let text = await Task.detached(priority: .userInitiated) {
                let extracted = PDFExtractor.extractText(from: url)
                if ok { url.stopAccessingSecurityScopedResource() }
                return extracted
            }.value
            if text.isEmpty {
                extractError = "no readable text found — try the photo tab instead."
            } else {
                extractedText = text
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            }
        } catch {
            extractError = "couldn't open that PDF. try again?"
        }
        isExtracting = false
    }

    private func handleDeckImport(_ result: Result<[URL], Error>) async {
        deckImportError  = nil
        deckImportSuccess = false
        do {
            guard let url = try result.get().first else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }

            let deck = try DeckExporter.importFile(from: url)
            guard !deck.cards.isEmpty else {
                deckImportError = "that deck appears to be empty."
                return
            }

            // Create a new Document + StudyItems from the exported deck
            let doc = Document(
                title: deck.title.isEmpty ? "Imported Deck" : deck.title,
                content: "",
                sourceType: .file
            )
            modelContext.insert(doc)
            for card in deck.cards {
                let item = StudyItem(question: card.question, answer: card.answer)
                item.topic    = card.topic
                item.document = doc
                modelContext.insert(item)
            }
            try? modelContext.save()
            HapticManager.success()
            deckImportSuccess = true
            // Clear success hint after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            deckImportSuccess = false
        } catch {
            deckImportError = "couldn't read that file — make sure it's a .verbadeck or valid deck JSON."
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isExtracting = true
        extractError = nil
        if let data = try? await item.loadTransferable(type: Data.self),
           let img  = UIImage(data: data) {
            let text = await OCRExtractor.extractText(from: img)
            extractedText = text.isEmpty ? "" : text
            if text.isEmpty { extractError = "couldn't read text from that photo." }
        } else {
            extractError = "couldn't load the photo."
        }
        isExtracting = false
    }

    private func resetState() {
        title             = ""
        pastedText        = ""
        extractedText     = ""
        selectedPhoto     = nil
        extractError      = nil
        isExtracting      = false
        createdCardCount  = 0
        createdDocument   = nil
        pendingCards      = []
        isGenerating      = false
        showStudyNow      = false
        selectedGenType   = .flashcards
        deckImportError   = nil
        deckImportSuccess = false
        withAnimation(.verba) { step = .input }
    }
}

// MARK: - GeneratingView

private struct GeneratingView: View {
    let genType: StudyGenType

    private var stages: [(icon: String, message: String)] {
        switch genType {
        case .flashcards:
            return [
                ("doc.text.magnifyingglass", "reading your notes…"),
                ("brain",                    "finding the key concepts…"),
                ("rectangle.on.rectangle",   "writing your flashcards…"),
                ("sparkles",                 "sharpening each card…"),
                ("checkmark.circle",         "almost ready…"),
            ]
        case .quickQuiz, .practiceExam:
            return [
                ("doc.text.magnifyingglass", "scanning your material…"),
                ("brain",                    "identifying likely exam topics…"),
                ("doc.text",                 "writing your questions…"),
                ("checkmark.seal",           "calibrating difficulty…"),
                ("checkmark.circle",         "almost ready…"),
            ]
        case .studyGuide:
            return [
                ("doc.text.magnifyingglass", "reading your notes…"),
                ("chart.bar",                "mapping the structure…"),
                ("list.bullet.rectangle",    "organizing your guide…"),
                ("sparkles",                 "polishing the outline…"),
                ("checkmark.circle",         "almost ready…"),
            ]
        case .teachMe:
            return [
                ("doc.text.magnifyingglass", "reading your notes…"),
                ("brain",                    "building a learning path…"),
                ("person.wave.2",            "planning each explanation…"),
                ("sparkles",                 "making it click…"),
                ("checkmark.circle",         "almost ready…"),
            ]
        case .keyConcepts:
            return [
                ("doc.text.magnifyingglass", "scanning your material…"),
                ("brain",                    "identifying must-know terms…"),
                ("sparkles",                 "writing clear definitions…"),
                ("checkmark.circle",         "almost ready…"),
                ("checkmark.circle",         "done…"),
            ]
        }
    }

    @State private var stageIndex  = 0
    @State private var textOpacity = 1.0
    @State private var mascotScale = 0.85

    private var stage: (icon: String, message: String) { stages[stageIndex] }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Mascot thinking
                VerbaMascot(mood: .thinking, size: 88, animate: true)
                    .scaleEffect(mascotScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                            mascotScale = 1
                        }
                    }

                VStack(spacing: 10) {
                    // Stage label with icon
                    HStack(spacing: 8) {
                        Image(systemName: stage.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(VerbaTheme.green)
                        Text(stage.message)
                            .font(VerbaFont.syne(.medium, size: 16))
                            .foregroundStyle(VerbaTheme.ink)
                    }
                    .opacity(textOpacity)
                    .animation(.easeInOut(duration: 0.2), value: textOpacity)

                    // Warm dot progress
                    HStack(spacing: 7) {
                        ForEach(0..<stages.count, id: \.self) { i in
                            Capsule()
                                .fill(i <= stageIndex ? VerbaTheme.green : VerbaTheme.green.opacity(0.15))
                                .frame(width: i == stageIndex ? 18 : 6, height: 6)
                                .animation(.verba, value: stageIndex)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Reassuring footer
            Text("this usually takes 10–30 seconds")
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.muted.opacity(0.7))
                .padding(.bottom, 52)
        }
        .verbaBackground()
        .onAppear { startCycling() }
    }

    private func startCycling() {
        guard stageIndex < stages.count - 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.18)) { textOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                stageIndex = min(stageIndex + 1, stages.count - 1)
                withAnimation(.easeIn(duration: 0.18)) { textOpacity = 1 }
                startCycling()
            }
        }
    }
}
