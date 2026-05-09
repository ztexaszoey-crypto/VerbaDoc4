import SwiftUI

struct TutorView: View {
    let item: StudyItem

    @Environment(\.dismiss) private var dismiss

    @State private var hintLevel = 0
    @State private var messages: [TutorMessage] = []
    @State private var showFullAnswer = false

    private let maxHints = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            questionCard

                            ForEach(messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if messages.isEmpty {
                                tutorIntroCard
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                actionBar
                    .padding()
            }
            .navigationTitle("Tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "face.smiling.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(VerbaTheme.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Verba Tutor")
                    .font(.headline)
                Text("Ask for hints anytime")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Question Card

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Question", systemImage: "questionmark.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(item.question)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .solidCard()
    }

    // MARK: - Tutor Intro Card

    private var tutorIntroCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "face.smiling.fill")
                .font(.system(size: 28))
                .foregroundStyle(VerbaTheme.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hi! I'm here to help.")
                    .font(.subheadline.bold())
                Text("Tap \"Give me a hint\" to get guidance without revealing the full answer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .solidCard()
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: TutorMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .tutor {
                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(VerbaTheme.green)
            } else {
                Spacer()
            }

            Text(message.content)
                .font(.subheadline)
                .padding(10)
                .background(message.role == .tutor ? Color(.secondarySystemBackground) : VerbaTheme.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, alignment: message.role == .tutor ? .leading : .trailing)

            if message.role == .student {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 12) {
            if showFullAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Answer", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(VerbaTheme.green)
                    Text(item.answer)
                        .font(.headline)
                        .foregroundStyle(VerbaTheme.green)
                    Text(item.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .solidCard()
            } else {
                HStack(spacing: 12) {
                    Button {
                        requestHint()
                    } label: {
                        Label("Give me a hint", systemImage: "lightbulb")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VerbaButtonStyle(filled: false))
                    .disabled(hintLevel >= maxHints)

                    Button {
                        revealAnswer()
                    } label: {
                        Label("Show answer", systemImage: "eye.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VerbaButtonStyle())
                }
            }
        }
    }

    // MARK: - Hint Logic

    private func requestHint() {
        HapticManager.impact()
        hintLevel += 1

        let hint: String
        switch hintLevel {
        case 1:
            let words = item.answer.split(separator: " ")
            let firstLetter = words.first.map { String($0.prefix(1)) + "..." } ?? "..."
            hint = "The answer starts with: \(firstLetter)"
        case 2:
            let answer = item.answer
            let half = answer.prefix(max(1, answer.count / 2))
            hint = "The first part of the answer is: \(half)..."
        case 3:
            hint = "Full context: \(item.explanation)"
        default:
            hint = "You've used all your hints. Try revealing the answer!"
        }

        messages.append(TutorMessage(role: .student, content: "Can you give me a hint?"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            messages.append(TutorMessage(role: .tutor, content: hint))
        }
    }

    private func revealAnswer() {
        HapticManager.success()
        withAnimation { showFullAnswer = true }
        messages.append(TutorMessage(role: .student, content: "Show me the answer."))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            messages.append(TutorMessage(role: .tutor, content: "Here's the full answer below! 👇"))
        }
    }
}
