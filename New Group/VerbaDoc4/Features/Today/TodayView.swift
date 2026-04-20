import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(filter: #Predicate<StudyItem> { $0.nextReviewAt <= Date() }) private var dueItems: [StudyItem]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Due today: \(dueItems.count)")
                    .font(.title2.bold())

                NavigationLink("Start Practice") {
                    TodayPracticeView()
                }
                .buttonStyle(VerbaButtonStyle())

                Spacer()
            }
            .padding()
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
}
