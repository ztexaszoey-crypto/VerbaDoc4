import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(filter: #Predicate<StudyItem> { $0.nextReviewAt <= Date() }, sort: \.nextReviewAt) private var dueItems: [StudyItem]

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
