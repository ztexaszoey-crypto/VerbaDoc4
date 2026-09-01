import SwiftUI
import SwiftData

// MARK: - CardEditView
//
// Full card editor — edit question/answer, regenerate with AI, or delete.
// Presented as a sheet from DocumentDetailView.
// All writes are committed immediately and saved to SwiftData on dismiss.

struct CardEditView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - Props

    let item: StudyItem
    let document: Document

    // MARK: - Local edit state (pending until saved)

    @State private var question: String
    @State private var answer: String
    @State private var showDeleteConfirm = false
    @State private var isRegenerating = false
    @State private var regenError: String? = nil

    @FocusState private var questionFocused: Bool
    @FocusState private var answerFocused: Bool

    // MARK: - Init

    init(item: StudyItem, document: Document) {
        self.item = item
        self.document = document
        _question = State(initialValue: item.question)
        _answer   = State(initialValue: item.answer)
    }

    // MARK: - Computed

    private var hasChanges: Bool {
        question.trimmingCharacters(in: .whitespacesAndNewlines) != item.question ||
        answer.trimmingCharacters(in: .whitespacesAndNewlines)   != item.answer
    }

    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasChanges
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // Mastery context — student knows which card this is
                        masteryBadge
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        // Question field
                        editorSection(
                            label: "question",
                            text: $question,
                            focused: $questionFocused,
                            placeholder: "what does this card ask?"
                        )

                        // Answer field
                        editorSection(
                            label: "answer",
                            text: $answer,
                            focused: $answerFocused,
                            placeholder: "the correct answer"
                        )

                        // Regen error (if any)
                        if let err = regenError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 12))
                                Text(err)
                                    .font(VerbaFont.syne(.regular, size: 13))
                            }
                            .foregroundStyle(VerbaTheme.danger)
                            .padding(.horizontal, 20)
                        }

                        // AI regeneration
                        regenButton
                            .padding(.horizontal, 20)

                        Divider()
                            .padding(.horizontal, 20)

                        // Delete — separated visually from edit actions
                        deleteButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        dismiss()
                    }
                    .font(VerbaFont.syne(.regular, size: 15))
                    .foregroundStyle(isRegenerating ? VerbaTheme.muted.opacity(0.35) : VerbaTheme.muted)
                    .disabled(isRegenerating) // block dismiss mid-regen — AI write would land on dismissed item
                }

                ToolbarItem(placement: .principal) {
                    Text("edit card")
                        .font(VerbaFont.syne(.semibold, size: 16))
                        .foregroundStyle(VerbaTheme.ink)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("save") {
                        saveEdits()
                        dismiss()
                    }
                    .font(VerbaFont.syne(.semibold, size: 15))
                    .foregroundStyle(canSave ? VerbaTheme.green : VerbaTheme.muted)
                    .disabled(!canSave)
                }
            }
        }
        .alert("delete this card?", isPresented: $showDeleteConfirm) {
            Button("delete", role: .destructive) {
                deleteCard()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("this card and its study progress will be permanently removed.")
        }
    }

    // MARK: - Mastery Badge

    private var masteryBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(masteryColor)
                .frame(width: 7, height: 7)
            Text(item.masteryLevel.rawValue.lowercased())
                .font(VerbaFont.syne(.medium, size: 12))
                .foregroundStyle(masteryColor)
            Text("·")
                .foregroundStyle(VerbaTheme.muted)
            Text("\(item.mastery)% mastery")
                .font(VerbaFont.syne(.regular, size: 12))
                .foregroundStyle(VerbaTheme.muted)

            if item.consecutiveMisses >= 2 {
                Text("·")
                    .foregroundStyle(VerbaTheme.muted)
                Text("missed \(item.consecutiveMisses)× in a row")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.danger)
            }

            if item.isUserEdited {
                Text("·")
                    .foregroundStyle(VerbaTheme.muted)
                Text("edited")
                    .font(VerbaFont.syne(.regular, size: 12))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    private var masteryColor: Color {
        switch item.mastery {
        case 75...: return VerbaTheme.green
        case 40..<75: return VerbaTheme.orange
        default: return VerbaTheme.danger
        }
    }

    // MARK: - Editor Section

    private func editorSection(
        label: String,
        text: Binding<String>,
        focused: FocusState<Bool>.Binding,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(VerbaFont.syne(.semibold, size: 11))
                .foregroundStyle(VerbaTheme.muted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(VerbaFont.syne(.regular, size: 16))
                        .foregroundStyle(VerbaTheme.muted.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(VerbaFont.syne(.regular, size: 16))
                    .foregroundStyle(VerbaTheme.ink)
                    .tint(VerbaTheme.green)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .focused(focused)
            }
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                    .stroke(
                        focused.wrappedValue ? VerbaTheme.green.opacity(0.45) : VerbaTheme.border,
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Regen Button

    private var regenButton: some View {
        Button {
            Task { await regenerateCard() }
        } label: {
            HStack(spacing: 8) {
                if isRegenerating {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(VerbaTheme.green)
                } else {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 14, weight: .regular))
                }
                Text(isRegenerating ? "regenerating…" : "regenerate with AI")
                    .font(VerbaFont.syne(.medium, size: 14))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(VerbaButtonStyle(filled: false, backgroundColor: VerbaTheme.green))
        .disabled(isRegenerating)
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .regular))
                Text("delete this card")
                    .font(VerbaFont.syne(.medium, size: 14))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(VerbaButtonStyle(filled: false, backgroundColor: VerbaTheme.danger))
    }

    // MARK: - Actions

    private func saveEdits() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !a.isEmpty else { return }

        item.question     = q
        item.answer       = a
        item.isUserEdited = true
        // Clear cached explanation — content changed, cache is now stale
        item.aiExplanation = nil
        item.lastModified  = Date()   // stamp for CloudSyncEngine's LWW cursor
        try? modelContext.save()
        CloudSyncEngine.shared.enqueueStudyItemSync(id: item.id)   // push edit to Firestore
    }

    private func deleteCard() {
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }

    private func regenerateCard() async {
        guard !isRegenerating else { return }
        isRegenerating = true
        regenError = nil
        HapticManager.impact()

        await StudyGenerator.shared.regenerateSingleCard(item, in: document, context: modelContext)

        if let err = StudyGenerator.shared.errorMessage {
            regenError = err
        } else {
            // Sync local state from the mutated item
            question = item.question
            answer   = item.answer
            HapticManager.success()
        }

        isRegenerating = false
    }
}
