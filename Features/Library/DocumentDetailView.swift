import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    let document: Document

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gate = ProGate.shared
    @State private var showingStudy    = false
        @State private var showingNotes    = false
    @State private var showingGuide    = false
    @State private var showPaywall     = false
    @State private var selectedScope: DrillScope = .all
    @State private var shareItem: URL? = nil
    @State private var showShareSheet   = false
    @State private var shareTextContent: String? = nil

    private var readiness: ReadinessCalculator.Result {
        ReadinessCalculator.calculate(for: document.studyItems, examDate: document.examDate)
    }

    private var dueCount: Int {
        document.studyItems.filter { $0.nextReviewAt <= Date() }.count
    }

    var body: some View {
        CozyBackdrop {
            VStack(spacing: 0) {
                // Navigation bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("library")
                                .font(VerbaFont.syne(.medium, size: 15))
                        }
                        .foregroundStyle(VerbaTheme.cozyForest)
                    }

                    Spacer()

                    HStack(spacing: 14) {
                        // Share — free users get text share, Pro gets file export
                        Button {
                            if gate.canExport() {
                                if let url = try? DeckExporter.exportToFile(document) {
                                    shareItem = url
                                    showShareSheet = true
                                }
                            } else {
                                // Free: share as plain text so friends can see the deck
                                let text = shareText(for: document)
                                shareItem = nil
                                showShareSheet = true
                                shareTextContent = text
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        }

                        Image(systemName: document.sourceType.systemIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .sheet(isPresented: $showShareSheet) {
                    if let url = shareItem {
                        ShareSheet(items: [url])
                    } else if let text = shareTextContent {
                        ShareSheet(items: [text])
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header card
                        VStack(alignment: .leading, spacing: 12) {
                            Text(document.title)
                                .font(VerbaFont.serif(size: 24))
                                .foregroundStyle(VerbaTheme.cozyForest)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)

                            HStack(spacing: 16) {
                                statPill(
                                    icon: "rectangle.stack.fill",
                                    value: "\(document.studyItems.count)",
                                    label: "cards"
                                )
                                statPill(
                                    icon: "clock.fill",
                                    value: "\(dueCount)",
                                    label: "due"
                                )
                                statPill(
                                    icon: "chart.bar.fill",
                                    value: "\(readiness.score)%",
                                    label: readiness.label
                                )
                            }
                        }
                        .padding(20)
                        .cozyBlockCard(fill: VerbaTheme.cozySage)

                        // Study scope picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("study mode")
                                .font(VerbaFont.syne(.semibold, size: 13))
                                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                                .textCase(.uppercase)
                                .tracking(0.8)

                            HStack(spacing: 8) {
                                scopeButton("All", scope: .all)
                                scopeButton("Due (\(dueCount))", scope: .due)
                                scopeButton("Weak", scope: .weak)
                            }
                        }

                        // Primary study buttons
                        HStack(spacing: 10) {
                            Button("study now") { showingStudy = true }
                                .cozyBlockButtonStyle()

                            // PHASE-2 cull: document detail "quiz" entry hidden pending ExamModeView redesign with real LLM-generated distractors.
                        }

                        // Secondary resource buttons
                        HStack(spacing: 10) {
                            resourceButton(
                                label: "notes",
                                icon: "doc.text",
                                action: { showingNotes = true }
                            )
                            resourceButton(
                                label: "study guide",
                                icon: "list.bullet.rectangle",
                                action: { showingGuide = true }
                            )
                        }

                        // Cards list
                        if !document.studyItems.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("flashcards")
                                    .font(VerbaFont.syne(.semibold, size: 13))
                                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                                    .textCase(.uppercase)
                                    .tracking(0.8)

                                ForEach(document.studyItems, id: \.id) { item in
                                    studyItemRow(item: item)
                                }
                            }
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingStudy) {
            FlashcardStudyView(document: document, scope: selectedScope)
        }
        // PHASE-2 cull: ExamMode cover hidden — file preserved for future ExamMode worth shipping.
        .fullScreenCover(isPresented: $showingNotes) {
            NotesView(document: document)
        }
        .fullScreenCover(isPresented: $showingGuide) {
            StudyGuideView(document: document, scope: selectedScope)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func resourceButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(VerbaFont.syne(.semibold, size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .foregroundStyle(VerbaTheme.cozyForest)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .cozyBlockCard(fill: VerbaTheme.cozySage)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(value)
                    .font(VerbaFont.syne(.bold, size: 16))
            }
            .foregroundStyle(VerbaTheme.cozyForest)

            Text(label)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
        .frame(maxWidth: .infinity)
    }

    private func scopeButton(_ label: String, scope: DrillScope) -> some View {
        let isSelected: Bool = {
            switch (selectedScope, scope) {
            case (.all, .all), (.due, .due), (.weak, .weak): return true
            default: return false
            }
        }()

        return Button(label) {
            withAnimation(.verba) { selectedScope = scope }
        }
        .font(VerbaFont.syne(.medium, size: 13))
        .foregroundStyle(VerbaTheme.cozyForest)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .allowsTightening(true)
        .background(isSelected ? VerbaTheme.cozyLime : VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.cozyForest, lineWidth: 3)
        )
    }

    private func studyItemRow(item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.question)
                    .font(VerbaFont.syne(.medium, size: 14))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(2)

                Spacer()

                masteryBadge(item.mastery)
            }

            Text(item.answer)
                .font(VerbaFont.syne(.regular, size: 12))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .lineLimit(2)
        }
        .padding(14)
        .background(VerbaTheme.cozySage)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(VerbaTheme.cozyForest, lineWidth: 3)
        )
    }

    private func masteryBadge(_ mastery: Int) -> some View {
        let color: Color = mastery >= 80 ? VerbaTheme.green
            : mastery >= 50 ? VerbaTheme.orange
            : VerbaTheme.danger

        return Text("\(mastery)%")
            .font(VerbaFont.syne(.bold, size: 11))
            .foregroundStyle(VerbaTheme.cozyForest)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .background(color.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(VerbaTheme.cozyForest, lineWidth: 1.5)
            )
    }

    private func shareText(for doc: Document) -> String {
        var lines = ["\(doc.title)", "Made with VerbaDoc — verbadoc.app", ""]
        for (i, item) in doc.studyItems.prefix(20).enumerated() {
            lines.append("Q\(i + 1): \(item.question)")
            lines.append("A: \(item.answer)")
            lines.append("")
        }
        if doc.studyItems.count > 20 {
            lines.append("...and \(doc.studyItems.count - 20) more cards.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
