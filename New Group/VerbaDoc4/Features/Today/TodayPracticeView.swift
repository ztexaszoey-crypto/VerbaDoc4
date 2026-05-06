import SwiftUI

struct TodayPracticeView: View {
    @Environment(\.dismiss) private var dismiss

    let items: [StudyItem]

    @State private var index = 0
    @State private var showAnswer = false

    private var currentItem: StudyItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    var body: some View {
        VStack(spacing: 16) {
            if let currentItem {
                Text("Card \(index + 1) of \(items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text(currentItem.question)
                        .font(.title3.weight(.semibold))

                    if showAnswer {
                        Divider()
                        Text("Answer: \(currentItem.answer)")
                            .font(.headline)
                        Text(currentItem.explanation)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .verbaCard()

                if showAnswer {
                    HStack {
                        Button("Again") { rateCurrent(.again) }
                            .buttonStyle(VerbaButtonStyle(filled: false))
                        Button("Good") { rateCurrent(.good) }
                            .buttonStyle(VerbaButtonStyle())
                        Button("Easy") { rateCurrent(.easy) }
                            .buttonStyle(VerbaButtonStyle())
                    }
                } else {
                    Button("Show Answer") {
                        showAnswer = true
                    }
                    .buttonStyle(VerbaButtonStyle())
                }
            } else {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(VerbaTheme.success)
                    .font(.title2.bold())
                Button("Done") { dismiss() }
                    .buttonStyle(VerbaButtonStyle())
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private enum Rating {
        case again
        case good
        case easy
    }

    private func rateCurrent(_ rating: Rating) {
        guard let item = currentItem else { return }

        switch rating {
        case .again:
            item.reps = 0
            item.intervalDays = 0
            item.nextReviewAt = Date()
            item.lastRating = "again"
        case .good:
            item.reps += 1
            item.intervalDays = max(1, item.intervalDays + 1)
            item.nextReviewAt = Calendar.current.date(byAdding: .day, value: item.intervalDays, to: Date()) ?? Date()
            item.lastRating = "good"
        case .easy:
            item.reps += 1
            item.intervalDays = max(2, item.intervalDays + 3)
            item.nextReviewAt = Calendar.current.date(byAdding: .day, value: item.intervalDays, to: Date()) ?? Date()
            item.lastRating = "easy"
        }

        showAnswer = false
        index += 1
    }
}
