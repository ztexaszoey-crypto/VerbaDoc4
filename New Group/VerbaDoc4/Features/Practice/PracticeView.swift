import SwiftUI
import SwiftData

struct PracticeView: View {
    @Query(sort: \.createdAt, order: .reverse) private var items: [StudyItem]

    var body: some View {
        NavigationStack {
            List(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.question)
                        .font(.headline)
                    Text(item.answer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(item.nextReviewAt <= Date() ? "Due now" : "Scheduled")
                        .font(.caption2)
                        .foregroundStyle(item.nextReviewAt <= Date() ? .orange : .secondary)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("No study cards yet", systemImage: "rectangle.stack")
                }
            }
            .navigationTitle("Practice")
        }
    }
}
