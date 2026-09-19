import SwiftUI
import SwiftData

// MARK: - OnboardingView (FELIwS pastel-green migration)
//
// Two-page onboarding: magic moment + how-it-works. Both pages
// render on top of `PastelBackdrop` (cream gradient + drifting mint
// blobs + yellow flowers + paper grain), use `pastelCard()` for
// floating containers, `pastelPrimaryButtonStyle()` / chunky cream
// chips for actions, and dark-olive ink / medium-olive muted for
// type — every primitive drawn from the Phase 2 design system.

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.modelContext) private var modelContext

    @State private var showingStudy   = false
    @State private var demoDocument: Document? = nil
    @State private var page: Int      = 0

    var body: some View {
        CozyBackdrop {
            ZStack {
                TabView(selection: $page) {
                    magicPage.tag(0)
                    howItWorksPage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: page)

                VStack {
                    HStack {
                        Spacer()
                        Button("skip") { hasSeenOnboarding = true }
                            .font(VerbaFont.syne(.bold, size: 12))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(VerbaTheme.glossCream.opacity(0.92))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(VerbaTheme.oliveBorder, lineWidth: 1.5)
                            )
                            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                                    radius: 0, x: 0, y: 3)
                            .padding(.horizontal, 20)
                            .padding(.top, 56)
                    }
                    Spacer()

                    HStack(spacing: 8) {
                        ForEach(0..<2) { i in
                            let isActive = (page == i)
                            Capsule()
                                .fill(isActive ? VerbaTheme.ctaTop : VerbaTheme.oliveBorder.opacity(0.30))
                                .frame(width: isActive ? 22 : 7, height: 7)
                                .overlay(
                                    Capsule().stroke(VerbaTheme.oliveBorder.opacity(0.5), lineWidth: 1)
                                )
                                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: page)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .fullScreenCover(isPresented: $showingStudy, onDismiss: { hasSeenOnboarding = true }) {
            if let doc = demoDocument {
                FlashcardStudyView(document: doc, scope: .all)
            }
        }
    }

    // MARK: - Page 1: Magic moment

    private var magicPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            HStack(spacing: -10) {
                mascotBubble(VerbaMascot(mood: .happy, size: 88))
                    .zIndex(1)
            }
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("notes → flashcards\nin 30 seconds.")
                    .font(VerbaFont.title(size: 30, weight: .black))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Text("Paste anything. AI does the rest.\nNo setup. No templates. Just study.")
                    .font(VerbaFont.bodyRounded(size: 15, weight: .medium))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .cozyBlockCard(fill: VerbaTheme.cozySage)
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    seedAndLaunchDemo()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                        Text("See it in action")
                            .font(VerbaFont.syne(.bold, size: 17))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .cozyBlockButtonStyle()

                Button {
                    withAnimation { page = 1 }
                } label: {
                    Text("how does it work?")
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .background(
                            Capsule().fill(VerbaTheme.glossCream)
                        )
                        .overlay(
                            Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                        )
                        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                                radius: 0, x: 0, y: 3)
                        .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                                radius: 10, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    // MARK: - Page 2: How it works

    private var howItWorksPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            VStack(spacing: 6) {
                Text("how it works")
                    .font(VerbaFont.title(size: 28, weight: .black))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text("three steps to mastery")
                    .font(VerbaFont.bodyRounded(size: 14, weight: .medium))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
            .padding(.bottom, 24)

            VStack(spacing: 14) {
                stepCard(
                    number: "1",
                    icon: "doc.text.fill",
                    title: "drop in your notes",
                    detail: "PDF, photo, text, YouTube — AI reads it all"
                )
                stepCard(
                    number: "2",
                    icon: "sparkles",
                    title: "AI builds your deck",
                    detail: "Gemini generates 20 flashcards in seconds"
                )
                stepCard(
                    number: "3",
                    icon: "brain.head.profile",
                    title: "spaced repetition does the rest",
                    detail: "SM-2 algorithm resurfaces cards right before you forget"
                )
            }
            .padding(.horizontal, 22)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    hasSeenOnboarding = true
                } label: {
                    HStack(spacing: 10) {
                        Text("get started")
                            .font(VerbaFont.syne(.bold, size: 17))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .cozyBlockButtonStyle()

                Button {
                    withAnimation { page = 0 }
                } label: {
                    Text("back")
                        .font(VerbaFont.syne(.semibold, size: 14))
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .background(Capsule().fill(VerbaTheme.glossCream))
                        .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 2))
                        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                                radius: 0, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    // MARK: - Helpers

    /// A 3D mascot bubble — cream chip with olive border + chunky
    /// contact shadow. Used for the duck + capybara pair on page 1.
    private func mascotBubble<V: View>(_ content: V) -> some View {
        content
            .padding(14)
            .background(
                ZStack {
                    Circle().fill(VerbaTheme.glossCream)
                    Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2.5)
                }
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                    radius: 0, x: 0, y: 6)
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.16),
                    radius: 12, x: 0, y: 8)
    }

    /// A sticky-note chunky step card. Each step is a 20pt-corner
    /// cream chip with a chunky mint number bubble on the left.
    private func stepCard(number: String, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(VerbaTheme.cozyLime)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().stroke(VerbaTheme.cozyForest, lineWidth: 4)
                    )
                    .overlay(
                        Text(number)
                            .font(VerbaFont.syne(.bold, size: 17))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(VerbaFont.syne(.bold, size: 16))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text(detail)
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cozyBlockCard(fill: VerbaTheme.cozySage)
    }

    private func seedAndLaunchDemo() {
        let demoTitle = DemoDeck.title
        let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.title == demoTitle })
        if let existing = try? modelContext.fetch(descriptor), let first = existing.first {
            demoDocument = first
        } else {
            UserDefaults.standard.removeObject(forKey: DemoDeck.seededKey)
            demoDocument = DemoDeck.seed(into: modelContext)
        }
        showingStudy = true
    }
}
