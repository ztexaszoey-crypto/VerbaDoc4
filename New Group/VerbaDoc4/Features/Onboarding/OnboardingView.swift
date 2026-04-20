import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var page = 0

    private let pages: [String] = [
        "Turn your notes into study prompts.",
        "Practice each day and build streaks.",
        "Track progress and learn faster."
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(VerbaCharacter.default.greeting)
                .font(.title.bold())

            Text(pages[page])
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(VerbaButtonStyle(filled: false))
                }

                Button(page == pages.count - 1 ? "Get Started" : "Next") {
                    if page == pages.count - 1 {
                        hasOnboarded = true
                        HapticManager.success()
                    } else {
                        page += 1
                        HapticManager.impact()
                    }
                }
                .buttonStyle(VerbaButtonStyle())
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    OnboardingView()
}
