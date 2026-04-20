import SwiftUI

struct SettingsView: View {
    @AppStorage(AppState.hasOnboardedKey) private var hasOnboarded = false
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var appState: AppState
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Study") {
                    HStack {
                        Text("Current streak")
                        Spacer()
                        Text("\(streakManager.currentStreak) days")
                            .foregroundStyle(.secondary)
                    }

                    Button("Mark Today as Studied") {
                        streakManager.markStudyCompleted()
                    }
                }

                Section("Premium") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(appState.hasPremium ? "Unlocked" : "Free")
                            .foregroundStyle(appState.hasPremium ? VerbaTheme.green : .secondary)
                    }

                    if !appState.hasPremium {
                        Button("Upgrade") {
                            showPaywall = true
                        }
                    }
                }

                Section("App") {
                    Button("Show Onboarding Again") {
                        hasOnboarded = false
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView(appState: appState)
            }
        }
    }
}
