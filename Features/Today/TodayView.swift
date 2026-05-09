import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \StudyItem.nextReviewAt) private var allItems: [StudyItem]

    private var dueItems: [StudyItem] {
        let now = Date()
        return allItems.filter { $0.nextReviewAt <= now }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Due today")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("\(dueItems.count)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))

                NavigationLink {
                    TodayPracticeView(items: dueItems)
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(VerbaButtonStyle())
                .disabled(dueItems.isEmpty)

                if dueItems.isEmpty {
                    Text("No cards due right now. Add new material in Library.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Today")
        }
    }
}
