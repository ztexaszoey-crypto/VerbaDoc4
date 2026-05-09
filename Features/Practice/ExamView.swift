import SwiftUI
import SwiftData

struct ExamView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @Query(sort: [SortDescriptor(\Document.createdAt, order: .reverse)]) private var documents: [Document]

    @State private var selectedDocument: Document? = nil
    @State private var examItems: [StudyItem] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var examComplete = false
    @State private var correctCount = 0
    @State private var startTime: Date = Date()

    var body: some View {
        NavigationStack {
            if selectedDocument == nil {
                documentPickerView
            } else if examComplete {
                resultsView
            } else {
                examSessionView
            }
        }
    }

    // MARK: - Document Picker

    private var documentPickerView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(VerbaTheme.green)

            Text("Exam Mode")
                .font(.largeTitle.bold())

            Text("Choose a document to test your knowledge.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            if documents.isEmpty {
                ContentUnavailableView(
                    "No Documents Yet",
                    systemImage: "books.vertical",
                    description: Text("Add material in Library to start an exam.")
                )
            } else {
                List(documents) { document in
                    Button {
                        startExam(with: document)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title.isEmpty ? "Untitled" : document.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Label(document.sourceType.displayName, systemImage: document.sourceType.systemIcon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let count = document.studyItems?.count ?? 0
                            Text("\(count) cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled((document.studyItems ?? []).isEmpty)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Exam Mode")
    }

    // MARK: - Exam Session

    @ViewBuilder
    private var examSessionView: some View {
        if currentIndex < examItems.count {
            let item = examItems[currentIndex]
            VStack(spacing: 20) {
                ProgressView(value: Double(currentIndex), total: Double(examItems.count))
                    .tint(VerbaTheme.green)
                    .padding(.horizontal)

                Text("Question \(currentIndex + 1) of \(examItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    Text(item.question)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showAnswer {
                        Divider()
                        Text("Answer")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(item.answer)
                            .font(.headline)
                            .foregroundStyle(VerbaTheme.green)
                        if !item.explanation.isEmpty {
                            Text(item.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .verbaCard()
                .padding(.horizontal)

                if showAnswer {
                    HStack(spacing: 16) {
                        Button {
                            markAnswer(correct: false)
                        } label: {
                            Label("Incorrect", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VerbaButtonStyle(filled: false))

                        Button {
                            markAnswer(correct: true)
                        } label: {
                            Label("Correct", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VerbaButtonStyle())
                    }
                    .padding(.horizontal)
                } else {
                    Button("Reveal Answer") {
                        showAnswer = true
                        HapticManager.impact()
                    }
                    .buttonStyle(VerbaButtonStyle())
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Quit") { resetExam() }
                }
            }
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(scoreColor)

            Text("Exam Complete!")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                Text("\(correctCount) / \(examItems.count)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)

                Text(scoreMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Try Again") {
                if let doc = selectedDocument { startExam(with: doc) }
            }
            .buttonStyle(VerbaButtonStyle(filled: false))
            .padding(.horizontal)

            Button("Done") { resetExam() }
                .buttonStyle(VerbaButtonStyle())
                .padding(.horizontal)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        let ratio = examItems.isEmpty ? 0 : Double(correctCount) / Double(examItems.count)
        if ratio >= 0.8 { return VerbaTheme.green }
        if ratio >= 0.6 { return VerbaTheme.xpGold }
        return VerbaTheme.danger
    }

    private var scoreMessage: String {
        let ratio = examItems.isEmpty ? 0 : Double(correctCount) / Double(examItems.count)
        if ratio >= 0.8 { return "Excellent work! 🌟" }
        if ratio >= 0.6 { return "Good effort! Keep studying." }
        return "Keep practicing — you'll get there! 💪"
    }

    private func startExam(with document: Document) {
        examItems = (document.studyItems ?? []).shuffled()
        selectedDocument = document
        currentIndex = 0
        showAnswer = false
        examComplete = false
        correctCount = 0
        startTime = Date()
    }

    private func markAnswer(correct: Bool) {
        if correct { correctCount += 1 }
        xpManager.award(.reviewCard)
        showAnswer = false
        HapticManager.selection()

        if currentIndex + 1 >= examItems.count {
            examComplete = true
            HapticManager.success()
            recordSession()
        } else {
            currentIndex += 1
        }
    }

    private func resetExam() {
        selectedDocument = nil
        examItems = []
        currentIndex = 0
        showAnswer = false
        examComplete = false
        correctCount = 0
    }

    private func recordSession() {
        let duration = Date().timeIntervalSince(startTime)
        let session = StudySession(
            date: Date(),
            cardsReviewed: examItems.count,
            correctCount: correctCount,
            duration: duration
        )
        SessionTracker.shared.record(session: session)
    }
}
