import SwiftUI
import FirebaseFirestore

// MARK: - ChatView
//
// Real-time 1-to-1 DM thread. Messages stream from Firestore as they arrive.
// Keyboard-safe: ScrollView shifts up automatically.
// Optimistic send: message appears locally before Firestore confirms.

struct ChatView: View {
    let friendName : String
    let convID     : String

    @EnvironmentObject private var firebaseManager: FirebaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var messages   : [DMMessage] = []
    @State private var draft      : String = ""
    @State private var listener   : ListenerRegistration? = nil
    @State private var isSending  = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Message List ──────────────────────────────────────
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 8) {
                                if messages.isEmpty {
                                    emptyState
                                        .padding(.top, 60)
                                }
                                ForEach(messages) { msg in
                                    MessageBubble(message: msg)
                                        .id(msg.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .padding(.bottom, 8)
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    Divider().background(VerbaTheme.border)

                    // ── Input Bar ─────────────────────────────────────────
                    inputBar
                        .background(VerbaTheme.card)
                }
            }
            .navigationTitle(friendName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        listener?.remove()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .medium))
                            Text("friends")
                                .font(VerbaFont.syne(.regular, size: 14))
                        }
                        .foregroundStyle(VerbaTheme.green)
                    }
                }
            }
            .onAppear {
                fieldFocused = true
                listener = FirebaseManager.shared.listenToMessages(in: convID) { msgs in
                    messages = msgs
                }
            }
            .onDisappear { listener?.remove() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            VerbaMascot(mood: .happy, size: 56)
            VStack(spacing: 4) {
                Text("say hey 👋")
                    .font(VerbaFont.serif(size: 18))
                    .foregroundStyle(VerbaTheme.ink)
                Text("start the conversation")
                    .font(VerbaFont.syne(.regular, size: 13))
                    .foregroundStyle(VerbaTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("message…", text: $draft, axis: .vertical)
                .font(VerbaFont.syne(.regular, size: 15))
                .foregroundStyle(VerbaTheme.ink)
                .tint(VerbaTheme.green)
                .lineLimit(1...5)
                .focused($fieldFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(VerbaTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(VerbaTheme.border, lineWidth: 1)
                )

            Button {
                send()
            } label: {
                ZStack {
                    Circle()
                        .fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? VerbaTheme.muted.opacity(0.20)
                              : VerbaTheme.green)
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .animation(.verbaSnappy, value: draft.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Send

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft    = ""
        isSending = true
        Task {
            await FirebaseManager.shared.send(text: text, to: convID)
            isSending = false
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: DMMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isFromMe { Spacer(minLength: 48) }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 3) {
                if !message.isFromMe {
                    Text(message.senderName)
                        .font(VerbaFont.syne(.regular, size: 11))
                        .foregroundStyle(VerbaTheme.muted)
                        .padding(.leading, 4)
                }

                Text(message.text)
                    .font(VerbaFont.syne(.regular, size: 15))
                    .foregroundStyle(message.isFromMe ? .white : VerbaTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        message.isFromMe
                            ? VerbaTheme.green
                            : VerbaTheme.card
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(message.isFromMe ? Color.clear : VerbaTheme.border, lineWidth: 1)
                    )

                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(VerbaFont.syne(.regular, size: 10))
                    .foregroundStyle(VerbaTheme.muted.opacity(0.6))
                    .padding(.horizontal, 4)
            }

            if !message.isFromMe { Spacer(minLength: 48) }
        }
    }
}
