import SwiftUI

// MARK: - PracticeModePickerView
//
// Bottom sheet that intercepts "Study Now" so the user can pick a study
// surface: Flashcards / Multiple-Choice (Pro) / Open Answer / Study Guide.
//
// Every tile previews the destination surface with its own visual
// treatment so the picker never looks like "AI cards inside a giant
// rounded rectangle":
//
//   · Flashcards     → PAPER-CARD tile      (verba card with hairline
//                                             border, serif title, eyebrow
//                                             caption, mascot top-left,
//                                             "tap to study" accent rule)
//
//   · Multiple Choice → TEST-PAPER tile    (letter prefix "Q" on left,
//                                             hairline vertical divider,
//                                             PRO underline as accent
//                                             rule; identical grammar to
//                                             `ExamModeView` option rows)
//
//   · Open Answer    → TEST-PAPER tile      (same grammar, letter prefix
//                                             "A", no PRO accent)
//
//   · Study Guide    → REFERENCE-DOCUMENT  (eyebrow caption + hairline
//                                             rule above content + hairline
//                                             rule below + uppercase
//                                             "7 SECTIONS" footer; mirrors
//                                             `StudyGuideView` document
//                                             style)
//
// All four tiles share: cream `VerbaTheme.cozySage` background, hairline
// `Rectangle().stroke` border, no rounded 20pt corners, no shadows,
// no gradient pools, no floating pills. Reuses `PremiumBackground`
// for the sheet chrome so visual identity matches the Practice tab.

struct PracticeModePickerView: View {
    let document: Document
    let scope: DrillScope
    let onSelect: (PracticeMode) -> Void

    // Explicit memberwise init with default keeps every parameter
    // visible at every call site — see DrillScope.swift header for
    // why SwiftUI Views here don't rely on synthesized memberwise inits.
    init(
        document: Document,
        scope:    DrillScope       = .all,
        onSelect: @escaping (PracticeMode) -> Void
    ) {
        self.document = document
        self.scope    = scope
        self.onSelect = onSelect
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gate = ProGate.shared
    @State private var showPaywall = false

    // MARK: - Mode catalogue

    /// Three visual treatments correspond to the surfaces the user is
    /// being routed to. They share the same outer Button wrapper + the
    /// same hairline border, but each tile renders a different body.
    private enum ArtStyle {
        case paperCard           // Flashcards  ↔ paper-card destination
        case testPaper           // MC + Open Answer ↔ test-paper destination
        case referenceDocument   // Study Guide ↔ reference-document destination
    }

    private struct ModeCard: Identifiable {
        let id = UUID()
        let mode: PracticeMode
        let title: String
        let subtitle: String
        let eyebrow: String       // small uppercase tracking caption
        let icon: String
        let mood: VerbaMascot.Mood?
        let usesDuck: Bool
        let isPro: Bool
        let artStyle: ArtStyle
    }

    private var cards: [ModeCard] {
        [
            ModeCard(mode: .flashcard,
                     title: "Flashcards",
                     subtitle: "Classic recall, swipe to grade",
                     eyebrow: "PAPER CARD",
                     icon: "rectangle.stack.fill",
                     mood: .happy, usesDuck: false, isPro: false,
                     artStyle: .paperCard),
            // PHASE-2 cull: Multiple-choice ModeCard hidden — ExamModeView's distractor generation not production-grade yet.
            ModeCard(mode: .quizOpenAnswer,
                     title: "Open answer",
                     subtitle: "Type to verify, self-grade",
                     eyebrow: "QUIZ · OPEN ANSWER",
                     icon: "keyboard.fill",
                     mood: .calm, usesDuck: false, isPro: false,
                     artStyle: .testPaper),
            ModeCard(mode: .studyGuide,
                     title: "Study guide",
                     subtitle: "Topic review sheet + stats",
                     eyebrow: "REFERENCE SHEET",
                     icon: "list.bullet.rectangle.portrait.fill",
                     mood: nil, usesDuck: true, isPro: false,
                     artStyle: .referenceDocument),
        ]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            CozyBackdrop {
                Color.clear
            }

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                Spacer(minLength: 20)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14),
                              GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(cards) { card in
                        tile(card)
                    }
                }
                .padding(.horizontal, 18)

                Spacer(minLength: 20)

                footer
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose study mode")
                    .font(VerbaFont.serif(size: 24))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text("\(document.studyItems.count) cards · \(document.title)")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close mode picker")
        }
    }

    // MARK: - Tile (shared wrapper)

    private func tile(_ card: ModeCard) -> some View {
        Button {
            tap(card)
        } label: {
            Group {
                switch card.artStyle {
                case .paperCard:         paperCardTile(card)
                case .testPaper:         testPaperTile(card)
                case .referenceDocument: referenceTile(card)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .background(VerbaTheme.cozySage)
            .overlay(
                Rectangle()
                    .stroke(VerbaTheme.border.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel(for: card))
    }

    private func tap(_ card: ModeCard) {
        HapticManager.light()
        if card.isPro && !gate.canUseExamMode() {
            showPaywall = true
            return
        }
        onSelect(card.mode)
    }

    // MARK: - Paper-card tile (Flashcards)

    /// Mirrors `FlashcardStudyView.premiumCardSurface` layout:
    /// cream paper, eyebrow caption, big serif title, bottom hairline
    /// accent rule + tiny "tap to study" caption.
    private func paperCardTile(_ card: ModeCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if let mood = card.mood {
                    VerbaMascot(mood: mood, size: 42)
                } else if card.usesDuck {
                    CapyScholar(size: 42)
                } else {
                    Color.clear.frame(width: 42, height: 42)
                }
                Spacer(minLength: 8)
                Text(card.eyebrow)
                    .font(VerbaFont.syne(.bold, size: 9))
                    .tracking(1.8)
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(VerbaFont.serif(size: 22))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(card.subtitle)
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(VerbaTheme.cozyLime.opacity(0.7))
                .frame(height: 1)
                .padding(.trailing, 70)
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("tap to study")
                    .font(VerbaFont.syne(.medium, size: 10))
                    .tracking(0.6)
            }
            .foregroundStyle(VerbaTheme.cozyLime)
            .padding(.top, 6)
        }
        .padding(14)
    }

    // MARK: - Test-paper tile (MC + Open Answer)

    /// Mirrors `ExamModeView.optionButton` layout: bold letter prefix
    /// on the LEFT (SAT-style answer sheet), vertical hairline divider,
    /// then eyebrow + title + subtitle on the right. PRO accent renders
    /// as a short orange underline rule under the title — no rounded
    /// orange pill.
    private func testPaperTile(_ card: ModeCard) -> some View {
        let locked = card.isPro && !gate.canUseExamMode()
        let prefix: String = (card.mode == .quizMultipleChoice) ? "Q" : "A"
        let accent: Color = locked ? VerbaTheme.cozyOliveSubtext
                          : (card.isPro ? VerbaTheme.orange : VerbaTheme.cozyLime)

        return HStack(alignment: .top, spacing: 0) {
            // Letter prefix — plain bold typography, no circle wrapper.
            Text(prefix)
                .font(VerbaFont.syne(.bold, size: 28))
                .tracking(0.5)
                .foregroundStyle(accent)
                .frame(width: 38)
                .padding(.top, 2)

            // Vertical hairline between letter and content.
            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.eyebrow)
                        .font(VerbaFont.syne(.bold, size: 9))
                        .tracking(1.8)
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if card.isPro {
                        Text("PRO")
                            .font(VerbaFont.syne(.bold, size: 9))
                            .tracking(1.8)
                            .foregroundStyle(VerbaTheme.orange)
                    }
                }
                Spacer(minLength: 0)
                Text(card.title)
                    .font(VerbaFont.serif(size: 20))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .lineLimit(2)
                Text(card.subtitle)
                    .font(VerbaFont.syne(.regular, size: 11))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(2)
                Spacer(minLength: 0)
                // Accent rule — orange for PRO (or muted when locked),
                // green for the free open-answer tile.
                Rectangle()
                    .fill(accent)
                    .frame(height: 1)
                    .padding(.trailing, 60)
                HStack(spacing: 6) {
                    Image(systemName: locked ? "lock.fill" : "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(locked ? "unlock to use" : "tap to answer")
                        .font(VerbaFont.syne(.medium, size: 10))
                        .tracking(0.6)
                }
                .foregroundStyle(locked ? VerbaTheme.cozyOliveSubtext : accent)
                .padding(.top, 6)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
        }
        .padding(.vertical, 14)
        .padding(.leading, 4)
    }

    // MARK: - Reference-document tile (Study Guide)

    /// Mirrors `StudyGuideView` document layout: eyebrow caption +
    /// small icon/mascot on the right of the header + 1pt hairline rule
    /// above the content + serif title + 1pt hairline rule below +
    /// uppercase "7 SECTIONS" footer line.
    private func referenceTile(_ card: ModeCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.eyebrow)
                    .font(VerbaFont.syne(.bold, size: 9))
                    .tracking(1.8)
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .textCase(.uppercase)
                Spacer()
                if let mood = card.mood {
                    VerbaMascot(mood: mood, size: 26)
                } else if card.usesDuck {
                    CapyScholar(size: 26)
                }
            }
            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)
                .padding(.top, 2)

            Spacer(minLength: 8)

            Text(card.title)
                .font(VerbaFont.serif(size: 22))
                .foregroundStyle(VerbaTheme.cozyForest)
            Text(card.subtitle)
                .font(VerbaFont.syne(.regular, size: 11))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .lineLimit(2)
                .padding(.top, 2)

            Spacer(minLength: 0)

            // Footer summarises what the destination document contains.
            HStack(spacing: 6) {
                Text("7 SECTIONS")
                    .font(VerbaFont.syne(.bold, size: 9))
                    .tracking(1.6)
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                Text("·")
                    .font(VerbaFont.syne(.regular, size: 9))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                Text("overview · timeline")
                    .font(VerbaFont.syne(.regular, size: 10))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VerbaTheme.cozyLime)
            }
            Rectangle()
                .fill(VerbaTheme.border.opacity(0.6))
                .frame(height: 1)
        }
        .padding(14)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Tap a mode · drag down to go back")
            .font(VerbaFont.syne(.regular, size: 11))
            .tracking(0.4)
            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
    }

    // MARK: - A11y

    private func accessibilityLabel(for card: ModeCard) -> String {
        let locked = card.isPro && !gate.canUseExamMode()
        return "\(card.title) study mode · \(locked ? "locked, Pro required" : "available")"
    }
}
