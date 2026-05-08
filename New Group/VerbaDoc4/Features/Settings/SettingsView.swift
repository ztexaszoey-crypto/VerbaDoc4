import SwiftUI

struct SettingsView: View {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @AppStorage("notifications.hour") private var reminderHour = 9
    @AppStorage("groq.apiKey") private var groqAPIKey = ""

    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var xpManager: XPManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack {
                            Label("Identity & avatar", systemImage: "person.fill")
                            Spacer()
                            Text(xpManager.currentRank.name)
                                .font(.subheadline)
                                .foregroundStyle(xpManager.currentRank.color)
                        }
                    }
                }

                Section("Study") {
                    HStack {
                        Text("Current streak")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("\(streakManager.currentStreak) days")
                        }
                        .foregroundStyle(.secondary)
                    }

                    Stepper("Daily reminder: \(displayHour(reminderHour))", value: $reminderHour, in: 6...22)
                        .onChange(of: reminderHour) { _, newValue in
                            NotificationManager.shared.scheduleDailyReminder(hour: newValue)
                        }

                    SecureField("Groq API key", text: $groqAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Community") {
                    NavigationLink("Follow students & DM") {
                        CommunityView()
                    }
                }

                Section("Legal") {
                    NavigationLink("Terms of Service") {
                        TermsOfServiceView()
                    }
                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }
                }

                Section("App") {
                    Button("Show onboarding again") {
                        hasOnboarded = false
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func displayHour(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 1..<12: return "\(hour) AM"
        case 12: return "12 PM"
        default: return "\(hour - 12) PM"
        }
    }
}
