import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - UploadTabView
//
// Five import sources, one consistent flow:
//
//   ✨ AI       — paste any text, Claude generates pedagogically structured cards
//   📄 PDF      — pick from Files app, text extracted via PDFKit
//   📷 Photo    — camera or library, on-device Vision OCR (no internet needed)
//   🌐 Web      — paste a URL, article text is fetched and stripped
//   📋 Quizlet  — paste Quizlet export (tab-separated or any format)
//
// Every source funnels to the same card preview sheet before saving.
// After save: "study now" launches FlashcardStudyView directly.

struct UploadTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabRouter: TabRouter

    enum Source: CaseIterable {
        case ai, youtube, pdf, photo, web, quizlet
        var label: String {
            switch self {
            case .ai:      return "AI"
            case .youtube: return "YouTube"
            case .pdf:     return "PDF"
            case .photo:   return "Photo"
            case .web:     return "Web"
            case .quizlet: return "Quizlet"
            }
        }
        var icon: String {
            switch self {
            case .ai:      return "wand.and.stars"
            case .youtube: return "play.rectangle.fill"
            case .pdf:     return "doc.richtext"
            case .photo:   return "camera"
            case .web:     return "globe"
            case .quizlet: return "square.on.square"
            }
        }
    }

    @State private var source: Source = .ai
    @State private var deckTitle = ""
    @State private var examDate: Date? = nil
    @State private var showExamDatePicker = false
    @State private var extractedText = ""
    @State private var detectedFormat = ""

    // Generation state
    @State private var isGenerating = false
    @State private var generationError: String? = nil

    // Preview + save
    @State private var parsedCards: [QuizletImporter.Card] = []
    @State private var showPreview = false
    @State private var createdDocument: Document? = nil
    @State private var showStudy = false

    @State private var showPaywallFromLimit = false

    // Source-specific
    @State private var urlInput = ""
    @State private var isFetchingURL = false
    @State private var urlError: String? = nil

    // YouTube
    @State private var youtubeURL = ""
    @State private var isFetchingYouTube = false
    @State private var youtubeError: String? = nil
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var isRunningOCR = false
    @State private var showFilePicker = false
    @State private var isExtractingPDF = false
    @State private var pdfWarning: String? = nil

    var canGenerate: Bool {
        !deckTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !extractedText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        CozyBackdrop {
            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        sourcePicker
                            .padding(.horizontal, 20)

                        titleField
                            .padding(.horizontal, 20)

                        sourceContent
                            .padding(.horizontal, 20)

                        if let doc = createdDocument {
                            successBanner(doc)
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            CardPreviewSheet(cards: $parsedCards, title: deckTitle, onSave: saveCards)
        }
        .sheet(isPresented: $showPaywallFromLimit) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $showStudy) {
            if let doc = createdDocument {
                FlashcardStudyView(document: doc, scope: .all)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView { images in
                processImages(images)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                processImages([image])
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, UTType(filenameExtension: "verbadeck") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("add a deck")
                .font(VerbaFont.serif(size: 26))
                .foregroundStyle(VerbaTheme.cozyForest)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Source Picker

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Source.allCases, id: \.self) { s in
                    Button {
                        withAnimation(.verba) {
                            source = s
                            extractedText = ""
                            detectedFormat = ""
                            generationError = nil
                            urlError = nil
                            pdfWarning = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: s.icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(s.label)
                                .font(VerbaFont.syne(.semibold, size: 13))
                        }
                        .foregroundStyle(source == s ? .white : VerbaTheme.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(source == s ? VerbaTheme.green : VerbaTheme.card)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(source == s ? Color.clear : VerbaTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Title + Exam Date Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Deck title
            VStack(alignment: .leading, spacing: 8) {
                label("deck title")
                TextField("e.g. Biology Ch. 4 — Cell Division", text: $deckTitle)
                    .font(VerbaFont.syne(.regular, size: 16))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .recessedChannel(contentInset: .init(top: 14, leading: 16, bottom: 14, trailing: 16))
            }

            // Exam date (optional but nudged)
            VStack(alignment: .leading, spacing: 8) {
                label("exam date (optional)")
                Button {
                    withAnimation(.verba) { showExamDatePicker.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(examDate != nil ? VerbaTheme.amber : VerbaTheme.mediumOliveMuted)

                        Text(examDate.map { formatted($0) } ?? "set your exam date for smarter reminders")
                            .font(VerbaFont.syne(.regular, size: 15))
                            .foregroundStyle(examDate != nil ? VerbaTheme.darkOliveInk : VerbaTheme.mediumOliveMuted)

                        Spacer()

                        if examDate != nil {
                            Button {
                                withAnimation(.verba) { examDate = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .recessedChannel()
                }

                if showExamDatePicker {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { examDate ?? Date().addingTimeInterval(86400 * 14) },
                            set: { examDate = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(VerbaTheme.green)
                    .padding(12)
                    .background(VerbaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                    .overlay(stroke(VerbaTheme.border))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onChange(of: examDate) { _, _ in
                        withAnimation(.verba) { showExamDatePicker = false }
                    }
                }
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    // MARK: - Source Content (switched)

    @ViewBuilder
    private var sourceContent: some View {
        switch source {
        case .ai:      aiSource
        case .youtube: youtubeSource
        case .pdf:     pdfSource
        case .photo:   photoSource
        case .web:     webSource
        case .quizlet: quizletSource
        }
    }

    // MARK: ✨ AI Source

    @ViewBuilder
    private var aiSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("paste your notes")
            textBox(placeholder: "Paste lecture notes, textbook excerpts, study guides — anything.", text: $extractedText, monospace: false)
        }

        if !detectedFormat.isEmpty {
            formatBadge(detectedFormat)
        }

        // AI generation counter for free users
        if !ProGate.shared.isPro {
            let remaining = ProGate.shared.aiGenerationsRemaining
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(remaining > 3 ? VerbaTheme.green : VerbaTheme.orange)
                Text(remaining > 0 ? "\(remaining) free AI \(remaining == 1 ? "generation" : "generations") left" : "no free generations left")
                    .font(VerbaFont.syne(.medium, size: 12))
                    .foregroundStyle(remaining > 3 ? VerbaTheme.cozyOliveSubtext : VerbaTheme.orange)
                Spacer()
                if remaining <= 3 {
                    Button("upgrade →") { showPaywallFromLimit = true }
                        .font(VerbaFont.syne(.bold, size: 12))
                        .foregroundStyle(VerbaTheme.green)
                }
            }
        }

        generateButton(
            label: "generate with AI →",
            icon: "wand.and.stars"
        )

        if let err = generationError {
            errorBanner(err)
        }
    }

    // MARK: 📄 PDF Source

    @ViewBuilder
    private var pdfSource: some View {
        VStack(spacing: 12) {
            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 12) {
                    if isExtractingPDF {
                        ProgressView().tint(VerbaTheme.green)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(VerbaTheme.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isExtractingPDF ? "reading PDF…" : "choose PDF from Files")
                            .font(VerbaFont.syne(.semibold, size: 15))
                            .foregroundStyle(VerbaTheme.cozyForest)
                        Text("textbooks, papers, lecture slides")
                            .font(VerbaFont.syne(.regular, size: 13))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VerbaTheme.muted.opacity(0.5))
                }
                .padding(16)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(stroke(VerbaTheme.border))
            }
            .buttonStyle(.plain)
            .disabled(isExtractingPDF)

            if let warning = pdfWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(VerbaTheme.orange)
                        .font(.system(size: 12))
                    Text(warning)
                        .font(VerbaFont.syne(.regular, size: 13))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if !extractedText.isEmpty {
            extractedPreview
            generateButton(label: "generate cards from PDF →", icon: "wand.and.stars")
        }

        if let err = generationError { errorBanner(err) }
    }

    // MARK: 📷 Photo Source

    @ViewBuilder
    private var photoSource: some View {
        HStack(spacing: 12) {
            // Camera
            Button {
                showCamera = true
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(VerbaTheme.green)
                    Text("camera")
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Text("photo a page")
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(stroke(VerbaTheme.border))
            }
            .buttonStyle(.plain)

            // Photo Library
            Button {
                showPhotoPicker = true
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundStyle(VerbaTheme.green)
                    Text("library")
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Text("pick screenshot")
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(stroke(VerbaTheme.border))
            }
            .buttonStyle(.plain)
        }

        if isRunningOCR {
            HStack(spacing: 10) {
                ProgressView().tint(VerbaTheme.green)
                Text("reading text from image…")
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        }

        if !extractedText.isEmpty {
            extractedPreview
            generateButton(label: "generate cards from photo →", icon: "wand.and.stars")
        }

        if let err = generationError { errorBanner(err) }
    }

    // MARK: 🎬 YouTube Source

    @ViewBuilder
    private var youtubeSource: some View {
        // Pro gate
        if !ProGate.shared.isPro {
            VStack(spacing: 16) {                    HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(VerbaTheme.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube → Flashcards")
                            .font(VerbaFont.syne(.bold, size: 15))
                            .foregroundStyle(VerbaTheme.cozyForest)
                        Text("Paste any YouTube link and AI summarises the whole video into cards")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                }
                .padding(16)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(stroke(VerbaTheme.border))

                Button { showPaywallFromLimit = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("unlock with Pro")
                    }
                }
                .cozyBlockButtonStyle()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                label("youtube link")
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(VerbaTheme.amber)
                        .font(.system(size: 16))
                    TextField("https://youtube.com/watch?v=…", text: $youtubeURL)
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if isFetchingYouTube {
                        ProgressView().tint(VerbaTheme.green).scaleEffect(0.8)
                    }
                }
                .padding(14)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(stroke(VerbaTheme.border))

                Text("Works on any video with subtitles/captions enabled")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }

            Button {
                Task { await fetchYouTube() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isFetchingYouTube ? "arrow.2.circlepath" : "wand.and.stars")
                    Text(isFetchingYouTube ? "summarising video…" : "summarise & generate cards →")
                }
            }
        .cozyBlockButtonStyle()
        .disabled(youtubeURL.trimmingCharacters(in: .whitespaces).isEmpty || isFetchingYouTube)
        .opacity(youtubeURL.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1.0)

        if let err = youtubeError { errorBanner(err) }

            if !extractedText.isEmpty {
                extractedPreview
            }
        }
    }

    // MARK: 🌐 Web Source

    @ViewBuilder
    private var webSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("paste a URL")
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .font(.system(size: 14))
                TextField("https://en.wikipedia.org/wiki/…", text: $urlInput)
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if isFetchingURL {
                    ProgressView().tint(VerbaTheme.green).scaleEffect(0.8)
                }
            }
            .padding(14)
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(stroke(VerbaTheme.border))
        }

        Button {
            Task { await fetchURL() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                Text("fetch page")
            }
        }
        .cozyBlockButtonStyle()
        .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isFetchingURL)
        .opacity(urlInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1.0)

        if let err = urlError { errorBanner(err) }

        if !extractedText.isEmpty {
            extractedPreview
            generateButton(label: "generate cards from page →", icon: "wand.and.stars")
        }

        if let err = generationError { errorBanner(err) }
    }

    // MARK: 📋 Quizlet Source

    @ViewBuilder
    private var quizletSource: some View {
        // How-to steps
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array([
                "Open your Quizlet set → tap ··· → Export",
                "Keep defaults: Tab between term/definition, Newline between cards",
                "Copy all text, paste below"
            ].enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(VerbaFont.syne(.bold, size: 13))
                        .foregroundStyle(VerbaTheme.green)
                        .frame(width: 18)
                    Text(step)
                        .font(VerbaFont.syne(.regular, size: 13))
                        .foregroundStyle(VerbaTheme.cozyForest)
                }
            }
        }
        .padding(14)
        .background(VerbaTheme.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(stroke(VerbaTheme.green.opacity(0.18)))

        // Clipboard paste button
        Button {
            if let clip = UIPasteboard.general.string, !clip.isEmpty {
                withAnimation(.verba) {
                    extractedText = clip
                    detectedFormat = QuizletImporter.detectedFormat(clip)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                Text("paste from clipboard")
            }
            .font(VerbaFont.syne(.medium, size: 15))
            .foregroundStyle(VerbaTheme.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(VerbaTheme.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(stroke(VerbaTheme.green.opacity(0.20)))
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 8) {
            label("or paste here")
            textBox(placeholder: "term\tdefinition\nterm\tdefinition…", text: $extractedText, monospace: true)
                .onChange(of: extractedText) { _, text in
                    detectedFormat = text.isEmpty ? "" : QuizletImporter.detectedFormat(text)
                }
        }

        if !detectedFormat.isEmpty { formatBadge(detectedFormat) }

        // Quizlet import skips AI — parse directly for speed
        Button {
            let cards = QuizletImporter.parse(extractedText)
            if !cards.isEmpty {
                parsedCards = cards
                showPreview = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                Text("preview \(QuizletImporter.parse(extractedText).count) cards →")
            }
        }
        .cozyBlockButtonStyle()
        .disabled(!canGenerate)
        .opacity(!canGenerate ? 0.45 : 1.0)
    }

    // MARK: - Shared sub-views

    private var extractedPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("extracted text")
                Spacer()
                Text("\(extractedText.split(separator: " ").count) words")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
            Text(extractedText.prefix(400) + (extractedText.count > 400 ? "…" : ""))
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .lineLimit(6)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VerbaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
                .overlay(stroke(VerbaTheme.border))
        }
    }

    // Shown when offline (AI unavailable but local parser still works)
    private var offlineModeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(VerbaTheme.orange)
                .font(.system(size: 14))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("offline — using local parser")
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text("Connect to the internet for AI-powered card generation.")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
            Spacer()
        }
        .padding(12)
        .background(VerbaTheme.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(stroke(VerbaTheme.orange.opacity(0.20)))
    }

    private func generateButton(label: String, icon: String) -> some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: icon)
                }
                Text(isGenerating ? "generating…" : label)
            }
        }
        .cozyBlockButtonStyle()
        .disabled(!canGenerate || isGenerating)
        .opacity(!canGenerate ? 0.45 : 1.0)
    }

    private func successBanner(_ doc: Document) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(VerbaTheme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(doc.studyItems.count) cards saved")
                        .font(VerbaFont.syne(.semibold, size: 15))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Text(doc.title)
                        .font(VerbaFont.syne(.regular, size: 13))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .lineLimit(1)
                }
                Spacer()
            }
            Button("study now →") { showStudy = true }
                .cozyBlockButtonStyle()
            Button("back to library") { tabRouter.selected = .library }
                .font(VerbaFont.syne(.medium, size: 14))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
        .padding(16)
        .background(VerbaTheme.green.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(stroke(VerbaTheme.green.opacity(0.25)))
    }

    // MARK: - Actions

    private func generate() async {
        // SECURITY (Ian Lackey gap #6): per-minute throttle before any
        // external call. Prevents a user with a loop from burning 30+
        // free AI generations within seconds. Server-side spend cap on
        // Groq dashboard is the real stop; this layer prevents the UI
        // from letting the user try.
        guard RateLimiter.consume(.aiGeneration) else {
            await MainActor.run {
                generationError = "Whoa — too many AI requests. Take a breath and try again in a moment."
            }
            return
        }

        // Free tier: check AI generation limit before calling API
        if !ProGate.shared.canGenerateAI() {
            await MainActor.run {
                generationError = "You've used your \(ProGate.Limit.maxAIGenerations) free AI generations. Upgrade to Pro for unlimited."
            }
            showPaywallFromLimit = true
            return
        }

        isGenerating = true
        generationError = nil
        HapticManager.impact()

        do {
            let cards = try await CardGenerationService.shared.generate(
                from: extractedText,
                title: deckTitle
            )
            ProGate.shared.recordAIGeneration()
            await MainActor.run {
                parsedCards = cards.isEmpty ? [QuizletImporter.Card(question: "What is the main topic?", answer: extractedText.prefix(200).description)] : cards
                isGenerating = false
                showPreview = true
            }
        } catch {
            // SECURITY: never leak `error.localizedDescription` to UI.
            // FriendlyErrorMapper maps every Error to user-safe copy
            // and falls back to a context-appropriate generic message.
            await MainActor.run {
                generationError = FriendlyErrorMapper.message(for: error, in: .aiGeneration)
                isGenerating = false
            }
        }
    }

    private func fetchURL() async {
        isFetchingURL = true
        urlError = nil

        do {
            let result = try await WebImporter.fetch(urlString: urlInput)
            await MainActor.run {
                extractedText = result.text
                if deckTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                   let title = result.title {
                    deckTitle = title
                }
                isFetchingURL = false
            }
        } catch {
            await MainActor.run {
                urlError = error.localizedDescription
                isFetchingURL = false
            }
        }
    }

    private func fetchYouTube() async {
        isFetchingYouTube = true
        youtubeError = nil
        HapticManager.impact()

        do {
            guard let token = AuthService.shared.accessToken, !token.isEmpty else {
                throw URLError(.userAuthenticationRequired)
            }

            let url = URL(string: "\(AuthService.shared.supabaseEdgeFunctionURL)/functions/v1/youtube-to-cards")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["url": youtubeURL, "cardCount": 20] as [String: Any])

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                switch http.statusCode {
                case 401: throw NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired. Sign out and sign in again."])
                case 429: throw NSError(domain: "", code: 429, userInfo: [NSLocalizedDescriptionKey: "Too many requests. Wait a moment and try again."])
                case 503: throw NSError(domain: "", code: 503, userInfo: [NSLocalizedDescriptionKey: "AI is temporarily unavailable. Try again in a few minutes."])
                default:  throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error (\(http.statusCode)). Please try again."])
                }
            }

            let json = try JSONDecoder().decode(YouTubeCardsResponse.self, from: data)

            if let error = json.error { throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: error]) }

            let cards = (json.cards ?? []).map { QuizletImporter.Card(question: $0.question, answer: $0.answer) }
            guard !cards.isEmpty else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "No captions found on this video. Try a video with subtitles enabled, or paste the transcript manually using the AI tab."])
            }

            await MainActor.run {
                // Auto-fill deck title from video title
                if deckTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    deckTitle = json.title ?? "YouTube Summary"
                }
                extractedText = "YouTube transcript — \(json.transcriptLength ?? 0) characters"
                parsedCards = cards
                isFetchingYouTube = false
                HapticManager.success()
                showPreview = true
            }
        } catch {
            await MainActor.run {
                youtubeError = error.localizedDescription
                isFetchingYouTube = false
            }
        }
    }

    private func processImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isRunningOCR = true
        Task {
            if let result = await VisionOCR.recognize(images) {
                await MainActor.run {
                    extractedText = result.text
                    isRunningOCR = false
                }
            } else {
                await MainActor.run {
                    generationError = "No text found in the image. Try a clearer photo."
                    isRunningOCR = false
                }
            }
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            pdfWarning = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }
            let ext = url.pathExtension.lowercased()

            if ext == "verbadeck" {
                do {
                    let (title, cards) = try DeckExporter.importFromFile(url)
                    deckTitle = title
                    parsedCards = cards
                    showPreview = true
                } catch {
                    pdfWarning = "Couldn't import this deck file. It may be corrupted or from a newer version of VerbaDoc."
                }
                return
            }

            // PDF
            isExtractingPDF = true
            pdfWarning = nil

            // Security scope access for Files-picked URLs
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            if let result = PDFImporter.extract(from: url) {
                if result.isLikelyScanned {
                    pdfWarning = "This looks like a scanned PDF. Text extracted may be limited — try Photo OCR for better results."
                }
                if deckTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                   let pdfTitle = result.title {
                    deckTitle = pdfTitle
                }
                extractedText = result.text
                isExtractingPDF = false
            } else {
                pdfWarning = "Couldn't extract text from this PDF."
                isExtractingPDF = false
            }
        }
    }

    private func saveCards() {
        guard !parsedCards.isEmpty else { return }

        // Enforce free-tier deck limit before inserting anything
        let existingDeckCount = (try? modelContext.fetchCount(FetchDescriptor<Document>())) ?? 0
        if !ProGate.shared.canCreateDeck(existingCount: existingDeckCount) {
            showPaywallFromLimit = true
            return
        }

        HapticManager.impact()

        let doc = Document(
            title: deckTitle.trimmingCharacters(in: .whitespaces),
            content: extractedText,
            sourceType: .text
        )
        doc.examDate = examDate
        modelContext.insert(doc)

        // Enforce free-tier card limit per deck (trim silently to limit for free users)
        let allowedCards = parsedCards.filter { _ in
            ProGate.shared.canAddCard(currentCount: doc.studyItems.count)
        }
        for card in allowedCards {
            let item = StudyItem(
                question: card.question.trimmingCharacters(in: .whitespaces),
                answer: card.answer.trimmingCharacters(in: .whitespaces)
            )
            item.topic = card.topic
            item.document = doc
            doc.studyItems.append(item)
            modelContext.insert(item)
        }

        do {
            try modelContext.save()
        } catch {
            // Surface the error instead of silently discarding data
            generationError = "Failed to save deck: \(error.localizedDescription)"
            // Roll back the inserted objects so the DB stays consistent
            modelContext.delete(doc)
            return
        }

        // Phase 19 release wiring — fire "document uploaded"
        // cohort events the moment the deck persists to SwiftData.
        // `documentUploaded` fires per save; `firstDocumentUploaded`
        // is the activation milestone, gated by a UserDefaults flag
        // so a reinstall correctly resets the gate.
        let uploadProps = AnalyticsManager.EventProps(
            deckID: doc.id,
            cardCount: doc.studyItems.count,
            source: "upload"
        )
        AnalyticsManager.shared.track(.documentUploaded, props: uploadProps)

        // Per-user gate — see CardGenerationService for the rationale.
        let userHash: String
        if let uid = AuthService.shared.currentUser?.id {
            userHash = AnalyticsManager.hash(String(describing: uid))
        } else {
            userHash = "anon"
        }
        let firstDocKey = "verbadoc.firstDocumentUploadedFired.\(userHash)"
        if !UserDefaults.standard.bool(forKey: firstDocKey) {
            UserDefaults.standard.set(true, forKey: firstDocKey)
            AnalyticsManager.shared.track(.firstDocumentUploaded, props: uploadProps)
        }

        withAnimation(.verba) {
            createdDocument = doc
            extractedText = ""
            parsedCards = []
            deckTitle = ""
            examDate = nil
        }

        HapticManager.success()
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(VerbaFont.syne(.semibold, size: 12))
            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func textBox(placeholder: String, text: Binding<String>, monospace: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(monospace
                          ? .system(size: 14, design: .monospaced)
                          : VerbaFont.syne(.regular, size: 15))
                    .foregroundStyle(VerbaTheme.mediumOliveMuted.opacity(0.55))
                    .padding(14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(monospace
                      ? .system(size: 14, design: .monospaced)
                      : VerbaFont.syne(.regular, size: 15))
                .foregroundStyle(VerbaTheme.cozyForest)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(10)
        }
        .recessedChannel(contentInset: .init(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private func formatBadge(_ format: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(VerbaTheme.green)
            Text("detected: \(format)")
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(VerbaTheme.danger)
                .font(.system(size: 14))
            Text(msg)
                .font(VerbaFont.syne(.regular, size: 13))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VerbaTheme.danger.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
    }

    private func stroke(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous).stroke(color, lineWidth: 1)
    }
}

// MARK: - Card Preview Sheet

struct CardPreviewSheet: View {
    @Binding var cards: [QuizletImporter.Card]
    let title: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()
                List {
                    Section {
                        ForEach(cards.indices, id: \.self) { idx in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Text("\(idx + 1)")
                                        .font(VerbaFont.syne(.bold, size: 11))
                                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                                        .frame(width: 20)
                                    TextField("Question", text: $cards[idx].question, axis: .vertical)
                                        .font(VerbaFont.syne(.semibold, size: 14))
                                        .foregroundStyle(VerbaTheme.cozyForest)
                                        .lineLimit(4)
                                }
                                TextField("Answer", text: $cards[idx].answer, axis: .vertical)
                                    .font(VerbaFont.syne(.regular, size: 13))
                                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                                    .lineLimit(5)
                                    .padding(.leading, 28)
                                if !cards[idx].topic.isEmpty {
                                    Text(cards[idx].topic)
                                        .font(VerbaFont.syne(.semibold, size: 10))
                                        .foregroundStyle(VerbaTheme.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(VerbaTheme.green.opacity(0.10))
                                        .clipShape(Capsule())
                                        .padding(.leading, 28)
                                }
                            }
                            .padding(.vertical, 6)
                            .listRowBackground(VerbaTheme.card)
                        }
                        .onDelete { cards.remove(atOffsets: $0) }
                    } header: {
                        Text("\(cards.count) card\(cards.count == 1 ? "" : "s") · swipe left to delete · tap to edit")
                            .font(VerbaFont.syne(.regular, size: 12))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                            .textCase(.none)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title.isEmpty ? "preview" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save \(cards.count)") {
                        onSave()
                        dismiss()
                    }
                    .font(VerbaFont.syne(.semibold, size: 15))
                    .foregroundStyle(cards.isEmpty ? VerbaTheme.muted : VerbaTheme.green)
                    .disabled(cards.isEmpty)
                }
            }
        }
    }
}

// MARK: - Photo Picker (PHPickerViewController wrapper)

struct PhotoPickerView: UIViewControllerRepresentable {
    let onSelect: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 5
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelect: ([UIImage]) -> Void
        init(onSelect: @escaping ([UIImage]) -> Void) { self.onSelect = onSelect }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            var images: [UIImage] = []
            let group = DispatchGroup()
            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { self.onSelect(images) }
        }
    }
}

// MARK: - Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - YouTube response model

private struct YouTubeCardsResponse: Decodable {
    struct CardItem: Decodable {
        let question: String
        let answer: String
        let topic: String?
    }
    let cards: [CardItem]?
    let title: String?
    let videoId: String?
    let transcriptLength: Int?
    let error: String?
}
