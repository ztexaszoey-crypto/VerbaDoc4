import SwiftUI

// MARK: - GenerationReviewView
//
// Shown between AI generation and deck save.
// Users can edit question/answer text, delete bad cards, and approve the deck.
// Cards only hit SwiftData AFTER the user taps "save deck" — no partial writes.

struct GenerationReviewView: View {

    // MARK: - Props

    let genType: StudyGenType
    let onApprove: ([EditableCard]) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var cards: [EditableCard]
    @State private var expandedID: UUID? = nil
    @State private var showCancelConfirm = false
    @State private var isSaving = false

    // MARK: - Init

    init(
        initialCards: [EditableCard],
        genType: StudyGenType,
        onApprove: @escaping ([EditableCard]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.genType = genType
        self.onApprove = onApprove
        self.onCancel = onCancel
        _cards = State(initialValue: initialCards)
    }

    // MARK: - Computed

    /// Singular noun for one generated item, varies by study type.
    private var itemLabel: String {
        switch genType {
        case .flashcards:   return "card"
        case .quickQuiz:    return "question"
        case .practiceExam: return "question"
        case .studyGuide:   return "section"
        case .teachMe:      return "lesson"
        case .keyConcepts:  return "concept"
        }
    }

    private var saveLabel: String {
        let n = cards.count
        return "save \(n) \(itemLabel)\(n == 1 ? "" : "s")"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(VerbaTheme.border)
                    .frame(height: 1)

                if cards.isEmpty {
                    emptyState
                } else {
                    cardList
                }

                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
            }
        }
        .confirmationDialog(
            "start over?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("discard cards", role: .destructive) { onCancel() }
            Button("keep editing", role: .cancel) {}
        } message: {
            Text("your generated cards will be discarded.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("review your \(itemLabel)s")
                    .font(VerbaFont.serif(size: 24))
                    .foregroundStyle(VerbaTheme.ink)
                Text("edit or delete anything before saving. tap any item to expand.")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)
                    .lineSpacing(2)
            }

            Spacer()

            // Card count badge
            VStack(spacing: 2) {
                Text("\(cards.count)")
                    .font(VerbaFont.syne(.bold, size: 20))
                    .foregroundStyle(genType.color)
                Text(cards.count == 1 ? itemLabel : itemLabel + "s")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
    }

    // MARK: - Card List

    private var cardList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach($cards) { $card in
                    ReviewCardRow(
                        card: $card,
                        isExpanded: expandedID == card.id,
                        accentColor: genType.color,
                        onTap: {
                            withAnimation(.verba) {
                                expandedID = expandedID == card.id ? nil : card.id
                            }
                            HapticManager.selection()
                        },
                        onDelete: {
                            withAnimation(.verba) {
                                if expandedID == card.id { expandedID = nil }
                                cards.removeAll { $0.id == card.id }
                            }
                            HapticManager.impact()
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            VerbaMascot(mood: .thinking, size: 72)
            VStack(spacing: 6) {
                Text("no cards left")
                    .font(VerbaFont.serif(size: 20))
                    .foregroundStyle(VerbaTheme.ink)
                Text("you deleted everything. start over to generate a new set.")
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                guard !isSaving else { return }
                isSaving = true
                HapticManager.success()
                onApprove(cards)
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.white)
                    }
                    Text(isSaving ? "saving…" : saveLabel)
                        .frame(maxWidth: .infinity)
                }
            }
            .primaryButtonStyle()
            .disabled(cards.isEmpty || isSaving)

            Button("start over") {
                showCancelConfirm = true
            }
            .outlineButtonStyle(color: VerbaTheme.muted)
        }
    }
}

// MARK: - ReviewCardRow

private struct ReviewCardRow: View {

    @Binding var card: EditableCard
    let isExpanded: Bool
    let accentColor: Color
    let onTap: () -> Void
    let onDelete: () -> Void

    @FocusState private var questionFocused: Bool
    @FocusState private var answerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — always visible
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(accentColor.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)

                    Text(card.question)
                        .font(VerbaFont.syne(.medium, size: 14))
                        .foregroundStyle(VerbaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VerbaTheme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: edit fields + actions
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 14)

                    // Question editor
                    editField(
                        label: "question",
                        text: $card.question,
                        focused: $questionFocused
                    )

                    // Answer editor
                    editField(
                        label: "answer",
                        text: $card.answer,
                        focused: $answerFocused
                    )

                    // Delete button
                    Button(role: .destructive, action: onDelete) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                            Text("delete card")
                                .font(VerbaFont.syne(.medium, size: 12))
                        }
                        .foregroundStyle(VerbaTheme.danger)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r12, style: .continuous)
                .stroke(isExpanded ? accentColor.opacity(0.25) : VerbaTheme.border, lineWidth: 1)
        )
        .animation(.verba, value: isExpanded)
    }

    private func editField(
        label: String,
        text: Binding<String>,
        focused: FocusState<Bool>.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(VerbaFont.syne(.semibold, size: 10))
                .foregroundStyle(VerbaTheme.muted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 14)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text("enter \(label)…")
                        .font(VerbaFont.syne(.regular, size: 14))
                        .foregroundStyle(VerbaTheme.muted.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(VerbaFont.syne(.regular, size: 14))
                    .foregroundStyle(VerbaTheme.ink)
                    .tint(accentColor)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .focused(focused)
            }
            .background(VerbaTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VerbaTheme.r8, style: .continuous)
                    .stroke(focused.wrappedValue ? accentColor.opacity(0.5) : VerbaTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, 14)
        }
    }
}
