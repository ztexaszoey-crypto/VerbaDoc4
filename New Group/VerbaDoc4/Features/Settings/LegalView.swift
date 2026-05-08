import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terms of Service")
                    .font(.largeTitle.bold())
                Group {
                    Text("VerbaDoc4 helps you create and study flashcards from your own learning materials.")
                    Text("Use the app responsibly, upload only content you have the right to use, and avoid sharing harmful or abusive material through community messaging.")
                    Text("AI-generated responses are study aids, not guarantees of academic performance. Always verify important facts with your teacher or source material.")
                    Text("Service availability may change over time, and certain features depend on third-party services like Groq. We may suspend access for misuse or abuse.")
                    Text("Users should meet their local minimum age requirements for digital services, or use the app with parent or school permission where required.")
                    Text("These terms are governed by the laws applicable where the service operator is based, and disputes should be addressed first through good-faith support resolution.")
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.largeTitle.bold())
                Group {
                    Text("Profile details, reminders, streaks, and community follow state are stored locally on your device.")
                    Text("When you provide a Groq API key and generate cards with AI, your source text is sent to Groq for processing.")
                    Text("Notification preferences are used only to schedule local study reminders. VerbaDoc4 does not sell your personal data.")
                    Text("If you reset the app or remove it from your device, locally stored profile data may be deleted. Community sample chats are mock local data, not a hosted messaging service.")
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
