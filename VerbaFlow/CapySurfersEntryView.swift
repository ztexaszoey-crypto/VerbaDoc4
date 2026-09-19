import SwiftUI
import SwiftData

// MARK: - CapySurfersEntryView
// Play hub: Capy Surfers runner + Quiz Portal + Classic Mode bridge.
//
// Classic Mode launches the older top-down VerbaFlowGameView, providing a
// dedupe bridge between the two parallel runner subsystems in this folder
// without deleting any files.

struct CapySurfersEntryView: View {    @StateObject private var state = CapySurfersState()
    @State private var showGame      = false
    @State private var showShop      = false
    @State private var showQuizSetup = false
    @State private var showClassic   = false
    // Phase 15 — Top Up sheet driven from this card. Voluntary 1-question
    // refuel quiz that fills the capy's tank via RefuelSessionView.
    @State private var showTopUp     = false
    // Phase 16.5 — bankBaseline captures bankedSeconds at the moment
    // the user taps Top Up. onComplete compares the delta to decide
    // success/error/silent haptic. Threshold-based (energy > 0) check
    // misfired when the bank was already non-empty — wrong answer
    // could leave juice at e.g. 10 (already-banked 15 - 5 wrong) and
    // trigger success chime.
    @State private var bankBaseline : Double = 0

    @Query private var allDocuments: [Document] 

    var body: some View {
        CozyBackdrop {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 6) {
                        CapyScholar(size: 90)
                            .padding(.top, 56)

                        Text("Play")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("study games · quiz portal · capy surfers")
                            .font(VerbaFont.syne(.medium, size: 12))
                            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                            .tracking(0.3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    // ── Stats row ─────────────────────────────────────────
                    HStack(spacing: 12) {
                        statChip(label: "best run", value: state.highScore > 0 ? "\(state.highScore)m" : "—")
                        statChip(label: "watermelons", value: "\(state.totalMelons)")
                        statChip(label: "decks", value: "\(allDocuments.count)")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // ── Capy Surfers card ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Capy Surfers")
                                    .font(.system(size: 22, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("endless runner · dodge obstacles · collect melons")
                                    .font(VerbaFont.syne(.medium, size: 12))
                                    // Sub-labels inside the terracotta card use
                                    // cozyForest so we satisfy WCAG AA-body
                                    // (≈4.7:1 vs #D97706). White headlines pass
                                    // AA-Large but fail AA-body at 11–12pt.
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            Spacer()
                            WaveIconView(size: 32, color: .white)
                        }
                        .padding(.bottom, 16)

                        // Skin preview
                        HStack(spacing: 10) {
                            SkinBadgeView(skin: state.equippedSkin, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.equippedSkin.name)
                                    .font(VerbaFont.syne(.bold, size: 13))
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("active skin")
                                    .font(VerbaFont.syne(.regular, size: 11))
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            if state.highScore > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack(spacing: 4) {
                                        TrophyIconView(size: 12, color: .white)
                                        Text("\(state.highScore)m")
                                            .font(VerbaFont.syne(.bold, size: 13))
                                            .foregroundStyle(VerbaTheme.cozyForest)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                    Text("personal best")
                                        .font(VerbaFont.syne(.regular, size: 11))
                                        .foregroundStyle(VerbaTheme.cozyForest)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        }
                        .padding(.bottom, 16)

                        HStack(spacing: 10) {
                            // Phase 6: Surf Now uses the cozy 3D lime block
                            // (replaces the frosted-glass slab). Solid fill,
                            // solid forest stroke, offset base — no glass,
                            // no gloss, no inner shadows.
                            Button {
                                HapticManager.medium()
                                showGame = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Surf Now")
                                        .font(.system(size: 17, weight: .black, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .cozyBlockButtonStyle(fill: VerbaTheme.cozyLime)
                            }

                            // Shop button — sage variant of the same 3D
                            // block so the visual weight balances.
                            Button {
                                HapticManager.light()
                                showShop = true
                            } label: {
                                HStack(spacing: 6) {
                                    ShopCartIconView(size: 16, color: VerbaTheme.cozyForest)
                                    Text("Shop")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .cozyBlockButtonStyle(fill: VerbaTheme.cozySage)
                            }
                        }

                        // Phase 15 — Top Up refill pill. Voluntary hop
                        // into RefuelSessionView to refill the capy's
                        // tank with one AI-generated question before
                        // pressing Surf Now. Visually subordinate to
                        // Surf Now so it doesn't compete for first
                        // attention, but reachable without leaving
                        // the Play tab.
                        Button {
                            HapticManager.light()
                            state.loadQuestions(from: allDocuments)
                            bankBaseline = state.bankedSeconds   // Phase 16.5 — capture pre-sheet baseline
                            showTopUp = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                Text("Top Up")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(VerbaTheme.cozySage.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke))
                        }
                        .padding(.top, 10)
                    }
                    .padding(20)
                    // Capy Surfers card → warm terracotta/amber chassis so
                    // .white text inside reads cleanly (Phase 11 brief).
                    // The Quiz Portal card uses the same warm family
                    // (cozyMustard) — the two accent cards now feel like
                    // siblings rather than one accent + one ghost box.
                    .background(VerbaTheme.cozyMustard)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // ── Quiz Portal card ──────────────────────────────────
                    Button {
                        HapticManager.medium()
                        showQuizSetup = true
                    } label: {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill")
                                        // Functional icon → cozyForest so it
                                        // matches the AA-body text colour
                                        // family on the terracotta card.
                                        .foregroundStyle(VerbaTheme.cozyForest)
                                        .font(.system(size: 14))
                                    Text("Quiz Portal")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        // Title (20pt black, ≥18pt regular weight)
                                        // stays white — passes AA-Large
                                        // (3.13:1 vs #D97706 ≥ 3:1).
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                Text("multiple choice or open answer · pick your notes · get tested")
                                    .font(VerbaFont.syne(.medium, size: 12))
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)

                                HStack(spacing: 6) {
                                    Label("Multiple choice", systemImage: "checkmark.circle.fill")
                                    Text("·")
                                    Label("Open answer", systemImage: "pencil")
                                }
                                .font(VerbaFont.syne(.medium, size: 11))
                                .foregroundStyle(VerbaTheme.cozyForest)
                                .padding(.top, 2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            // Phase 6: CapyScholar removed per directive;
                            // use CapyScholar (claymation capybara holding
                            // a flashcard) so the Quiz Portal reads as
                            // a single cohesive mascot across the app.
                            CapyScholar(size: 72)
                        }
                        .padding(20)
                        // Phase 6: Quiz Portal is the cozy MUSTARD brown
                        // (#C6893F) block per the latest spec — it reads
                        // as a warm earth-tone accent against the matcha
                        // backdrop, distinct from the sage cards and
                        // vibrant lime CTAs. 4.5pt forest stroke + offset
                        // (4, 5) 3D base. No gradients, no gloss.
                        .cozyBlockCard(
                            fill: VerbaTheme.cozyMustard,
                            ink: VerbaTheme.cozyForest,
                            cornerRadius: VerbaTheme.cozyRadius,
                            baseOffset: VerbaTheme.cozyOffset,
                            strokeWidth: VerbaTheme.cozyStroke
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    // ── How to play ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("how to play capy surfers")
                            .font(VerbaFont.syne(.bold, size: 13))
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .padding(.bottom, 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 12) {
                            tipPill("←  →", "change lane")
                            tipPill("↑", "jump")
                            tipPill("↓", "roll")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // ── Classic Mode bridge (dedupe: launch older top-down VerbaFlow runner) ───
                    Button {
                        HapticManager.light()
                        showClassic = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.system(size: 14))
                                .foregroundStyle(VerbaTheme.cozyForest)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Classic Mode")
                                    .font(VerbaFont.syne(.bold, size: 14))
                                    .foregroundStyle(VerbaTheme.cozyForest)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("top-down runner · 3 lanes · MCQ + typed answer")
                                    .font(VerbaFont.syne(.regular, size: 11))
                                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        // ── UNIFIED CREAM-BACKDROP CHASSIS ──
                        // Pairs: cozySage.fill(0.85) + cozyForest.stroke(cozyStroke).
                        // The fill alone is near-invisible on cream
                        // (#FFFFFF × 0.85 over #F4F6F0), so the chassis
                        // silhouette is lifted by the token-bound stroke
                        // (1.5pt full cozyForest opacity, ΔE ≈ 11). DO
                        // NOT edit fill or stroke independently — they
                        // are pinned together; loosening the stroke
                        // makes the stat chip / tip pill / Classic Mode
                        // button silently disappear on cream backdrop.
                        .background(VerbaTheme.cozySage.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke))
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            CapySurfersGameView(documents: allDocuments)
        }
        .fullScreenCover(isPresented: $showClassic) {
            VerbaFlowGameView(document: allDocuments.first)
        }
        .sheet(isPresented: $showShop) {
            CapySurfersShopView(state: state)
        }
        .sheet(isPresented: $showQuizSetup) {
            QuizSetupSheet(allDocuments: allDocuments)
        }
        // Phase 15 — voluntary 1-question top-up session. Sheet, not
        // fullScreen, because the brief said "Top up before running
        // button that opens the same quiz flow voluntarily" — the
        // voluntary path is dismissable; only the pre-game gate is
        // fullscreen + non-dismissable.
        .sheet(isPresented: $showTopUp) {
            RefuelSessionView(
                state: state,
                documents: allDocuments,
                questionCount: 1,
                onComplete: {
                    // Phase 16.5 — bank the top-up result so the next
                    // launch starts with energy > 0 instead of falling
                    // into the energy==0 freeze-trigger path. Refuel
                    // session answers wrote to `state.energy` (the
                    // juice alias) via state.submit, so we mirror the
                    // best result into bankedSeconds.
                    state.bankedSeconds = max(state.bankedSeconds, state.energy)
                    // discriminate by DELTA, not absolute: pre-banked scenario
                    // (bank=15 → wrong clamp to 10) would otherwise misfire success.
                    // Note — no redundant loss-fallback haptic here: state.submit
                    // already fires HapticManager.impact(.medium) on per-question
                    // wrong answers, so adding a second one at onComplete would
                    // cascade three impacts in <1s on every wrong-answer top-up.
                    let delta = state.bankedSeconds - bankBaseline
                    if delta > 0      { HapticManager.success() }
                    else if delta < 0 { HapticManager.error()   }
                    showTopUp = false
                },
                allowDismiss: true
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Helpers

    private func statChip(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(VerbaTheme.cozyForest)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(VerbaFont.syne(.medium, size: 10))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        // ── UNIFIED CREAM-BACKDROP CHASSIS ──
        // Pairs: cozySage.fill(0.85) + cozyForest.stroke(cozyStroke).
        // See Classic Mode button for the full token-pair rationale.
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke)
        )
    }

    private func tipPill(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(VerbaFont.syne(.bold, size: 11))
                .foregroundStyle(VerbaTheme.cozyForest)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(action)
                .font(VerbaFont.syne(.medium, size: 11))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // ── UNIFIED CREAM-BACKDROP CHASSIS ──
        // Pairs: cozySage.fill(0.85) + cozyForest.stroke(cozyStroke).
        // See Classic Mode button for the full token-pair rationale.
        .background(VerbaTheme.cozySage.opacity(0.85))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke)
        )
    }
}
