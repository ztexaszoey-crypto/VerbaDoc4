import SwiftUI
import SwiftData

struct PracticeView: View {
    @Query(sort: [SortDescriptor<StudyItem>(\.createdAt, order: .reverse)]) private var items: [StudyItem]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No study items", systemImage: "rectangle.stack")
                } else {
                    TodayPracticeView()
                }
            }
            .navigationTitle("Practice")
        }
    }
}

#Preview {
    PracticeView()
}
