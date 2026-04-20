import SwiftUI
import SwiftData

struct TodayPracticeView: View {
    @Query(filter: #Predicate<StudyItem> { $0.nextReviewAt <= Date() }) private var dueItems: [StudyItem]
    @State private var index = 0
    @State private var showAnswer = false

    var body: some View {
        VStack(spacing: 20) {
            if dueItems.isEmpty {
                ContentUnavailableView("No cards due", systemImage: "checkmark.circle")
            } else {
                let item = dueItems[min(index, dueItems.count - 1)]

                Text(item.question)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                if showAnswer {
                    Text(item.answer)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button(showAnswer ? "Hide Answer" : "Show Answer") {
                    showAnswer.toggle()
                }
                .buttonStyle(VerbaButtonStyle(filled: false))

                Button("Next") {
                    index = min(index + 1, dueItems.count - 1)
                    showAnswer = false
                }
                .buttonStyle(VerbaButtonStyle())
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Practice")
    }
}

#Preview {
    NavigationStack { TodayPracticeView() }
}
