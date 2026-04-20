import SwiftUI

struct SettingsView: View {
    @AppStorage("dailyGoal") private var dailyGoal = 10

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Daily goal: \(dailyGoal)", value: $dailyGoal, in: 1...200)

                NavigationLink("Upgrade") {
                    PaywallView()
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
