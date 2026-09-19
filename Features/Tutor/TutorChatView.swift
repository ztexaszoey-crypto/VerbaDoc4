import SwiftUI

// MARK: - TutorChatView
//
// The AI tutor surface. Two things make this different from "a chat box
// wired to an LLM":
//
//  1. Answers are RETRIEVAL-GROUNDED. The question is embedded, compared
//     against the student's own indexed notes, and the best-matching
//     passages are folded into the prompt — so the tutor answers from
//     their material instead of generic model knowledge, and says which
//     parts came from the notes.
//
//  2. Transport goes through `AIChatRouter.shared.send(system:userPrompt:)`,
//     which fails over between Groq and NVIDIA NIM. A rate limit on one
//     provider is invisible here — the student never sees provider names
//     or 429s.
//
// Degradation is deliberate, not an error path: if nothing has been
// indexed yet, the tutor answers from general knowledge and LABELS that
// answer as ungrounded. `NoteVectorStore.index(...)` is not yet called
// from the upload flow, so today every answer takes that branch; wiring
// upload indexing upgrades the same screen with no changes here.
//
// PROMPT COPY lives in exactly one place — `NoteVectorStore
// .buildGroundedPrompt(question:context:)` — and the empty-context case
// already produces the "answer from general knowledge and say so plainly"
// wording. This view does not carry a second copy of it.

struct TutorChatView: View {

    @State private var turns: [TutorChatTurn] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: ErrorPresentation?
    @State private var lastPrompt: String?

    @FocusState private var inputFocused: Bool

    // MARK: - Body

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                transcript
                inputBar
            }
        }
        .errorBanner(
            presentation: error,
            onRetry: { Task { await retryLast() } },
            onDismiss: { error = nil }
        )
        .onAppear { if turns.isEmpty { inputFocused = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("verba")
                    .font(VerbaFont.serif(size: 26))
                    .foregroundStyle(VerbaTheme.ink)
                Text("answers from your own notes")
                    .font(VerbaFont.syne(.regular, size: 11))
                    .tracking(0.3)
                    .foregroundStyle(VerbaTheme.muted)
            }

            Spacer(minLength: 12)

            if !turns.isEmpty {
                Button {
                    HapticManager.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        turns.removeAll()
                        error = nil
                        lastPrompt = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("clear")
                            .font(VerbaFont.syne(.semibold, size: 11))
                    }
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(VerbaTheme.glossCream))
                    .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.5))
                }
                // Explicit style: a default-styled Button inherits the global
                // accent, which is how "Surf Now" rendered system blue.
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the conversation")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if turns.isEmpty {
                        emptyState
                    } else {
                        ForEach(turns) { turn in
                            bubble(turn).id(turn.id)
                        }
                    }
                    if isSending {
                        thinkingRow.id(Self.thinkingAnchor)
                    }
                    Color.clear.frame(height: 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: isSending) { _, sending in
                if sending { scrollToEnd(proxy) }
            }
        }
    }

    private static let thinkingAnchor = "verba.tutor.thinking"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.22)) {
            if isSending {
                proxy.scrollTo(Self.thinkingAnchor, anchor: .bottom)
            } else if let last = turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(VerbaTheme.glossCream))
                    .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2))

                VStack(alignment: .leading, spacing: 3) {
                    Text("ask me anything")
                        .font(VerbaFont.syne(.bold, size: 15))
                        .foregroundStyle(VerbaTheme.ink)
                    Text("I'll explain it like a tutor, not a search result.")
                        .font(VerbaFont.syne(.regular, size: 12))
                        .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("TRY ONE OF THESE")
                    .font(VerbaFont.syne(.bold, size: 10))
                    .tracking(1.6)
                    .foregroundStyle(VerbaTheme.muted)

                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await send(suggestion) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(suggestion)
                                .font(VerbaFont.syne(.medium, size: 13))
                                .foregroundStyle(VerbaTheme.cozyForest)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(VerbaTheme.muted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VerbaTheme.glossCream)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(VerbaTheme.oliveBorder.opacity(0.35), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    private static let suggestions = [
        "Explain this topic like I'm seeing it for the first time",
        "Quiz me on what I just uploaded",
        "What's the difference between the two things I keep mixing up?"
    ]

    // MARK: - Bubbles

    @ViewBuilder
    private func bubble(_ turn: TutorChatTurn) -> some View {
        switch turn.role {
        case .student:
            HStack {
                Spacer(minLength: 44)
                Text(turn.text)
                    .font(VerbaFont.syne(.medium, size: 14))
                    .foregroundStyle(VerbaTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(VerbaTheme.cozyLime.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(VerbaTheme.oliveBorder.opacity(0.55), lineWidth: 1.5)
                    )
            }

        case .verba:
            VStack(alignment: .leading, spacing: 8) {
                Text(turn.text)
                    .font(VerbaFont.serif(size: 16))
                    .foregroundStyle(VerbaTheme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Image(systemName: turn.groundedInNotes ? "doc.text.fill" : "globe")
                        .font(.system(size: 9, weight: .semibold))
                    Text(turn.groundedInNotes
                         ? "from your notes"
                         : "general knowledge — upload notes to ground this answer")
                        .font(VerbaFont.syne(.regular, size: 10))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(VerbaTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VerbaTheme.glossCream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
            )
            .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                    radius: 0, x: 0, y: 4)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(VerbaTheme.cozyForest)
            Text("verba is thinking…")
                .font(VerbaFont.syne(.regular, size: 12))
                .foregroundStyle(VerbaTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // `prompt:` must be a `Text`, not a modified view — keep it bare.
            TextField("", text: $draft, prompt: Text("ask about your material…"), axis: .vertical)
                .font(VerbaFont.syne(.regular, size: 14))
                .foregroundStyle(VerbaTheme.ink)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(VerbaTheme.glossCream)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VerbaTheme.oliveBorder.opacity(0.7), lineWidth: 1.5)
                )
                .accessibilityLabel("Ask Verba a question")

            Button {
                Task { await send(draft) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? VerbaTheme.ink : VerbaTheme.muted)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(canSend ? VerbaTheme.cozyLime : VerbaTheme.glossCream))
                    .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2))
                    .shadow(color: VerbaTheme.oliveContactShadow.opacity(canSend ? 0.30 : 0.12),
                            radius: 0, x: 0, y: canSend ? 4 : 2)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [VerbaTheme.bgTop.opacity(0), VerbaTheme.bgBottom.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Sending

    private func retryLast() async {
        guard let prompt = lastPrompt else { return }
        // Drop the failed question so `send` can re-add it. Without this the
        // retry appends a SECOND identical student bubble, because the failure
        // path leaves the original one in the transcript.
        if let last = turns.last, last.role == .verba || last.text == prompt {
            turns.removeLast()
        }
        await send(prompt)
    }

    private func send(_ raw: String) async {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }

        HapticManager.light()
        error = nil
        draft = ""
        lastPrompt = question
        turns.append(TutorChatTurn(role: .student, text: question))
        isSending = true
        defer { isSending = false }

        // Grounded first: retrieve the passages most similar to the question
        // and fold them into the prompt. Any retrieval failure — nothing
        // indexed yet, or a document that isn't ready — is a normal state,
        // not an error. Fall back to the SAME prompt builder with no context,
        // which already says "answer from general knowledge and say so".
        var prompt = NoteVectorStore.buildGroundedPrompt(question: question, context: [])
        var grounded = false
        do {
            prompt = try await NoteVectorStore.shared.groundedPrompt(for: question)
            grounded = true
        } catch is NoteIndexError {
            // Nothing indexed yet, or this document isn't ready. A normal
            // state, not a failure: keep the ungrounded prompt already built
            // above, which tells the model to answer from general knowledge
            // and say so.
        } catch is CancellationError {
            // The view went away mid-retrieval. Do not fire the chat request.
            return
        } catch {
            // A genuine failure — a transport error from the embedding call.
            // Surface it instead of re-sending the same broken request to the
            // chat endpoint and reporting whatever that returns.
            //
            // All THREE arms are required, not decorative: `send(_:)` is not
            // marked `throws`, so a `do` whose catch clauses are not
            // exhaustive is a compile error ("errors thrown from here are not
            // handled because the enclosing catch is not exhaustive").
            // Note also that the chat `do`/`catch` below is a SEPARATE
            // statement — a throw here is never seen by its catch clauses.
            self.error = ErrorPresentation(error, in: .aiGeneration)
            return
        }

        do {
            // The router owns provider choice AND failover. The provider it
            // returned is diagnostics only — never surfaced to the student.
            let reply = try await AIChatRouter.shared.send(
                system: AIChatRouter.defaultSystemPrompt,
                userPrompt: prompt
            )
            turns.append(
                TutorChatTurn(role: .verba, text: reply.text, groundedInNotes: grounded)
            )
            HapticManager.success()
        } catch is CancellationError {
            // The view went away mid-flight. Not a failure to report.
        } catch {
            self.error = ErrorPresentation(error, in: .aiGeneration)
        }
    }
}

// MARK: - Turn model

/// One exchange in the transcript.
///
/// Deliberately NOT `TutorMessage` from Models.swift: that type is a
/// storage/UI model with its own `role` enum, and reusing it here would
/// couple the chat UI to whatever persistence shape it grows. This is
/// view state only.
struct TutorChatTurn: Identifiable, Equatable {

    enum Role: Equatable {
        case student
        case verba
    }

    let id = UUID()
    let role: Role
    let text: String

    /// True when the reply came from retrieved note passages. Drives the
    /// "from your notes" attribution under the bubble.
    var groundedInNotes: Bool = false
}

// MARK: - Preview

#Preview("Tutor") {
    TutorChatView()
}
