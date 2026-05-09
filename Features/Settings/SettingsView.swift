import SwiftUI

struct SettingsView: View {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var xpManager: XPManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack {
                            Label("Identity", systemImage: "person.fill")
                            Spacer()
                            Text("Rank \(xpManager.currentRank.rawValue + 1)")
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

                    Button("Mark Today as Studied") {
                        streakManager.markStudyCompleted()
                    }
                }

                Section("App") {
                    Button("Show Onboarding Again") {
                        hasOnboarded = false
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
