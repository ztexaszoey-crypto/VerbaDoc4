import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    @State private var showRedeem = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(VerbaTheme.green)

                Text("VerbaDoc4 Premium")
                    .font(.title.bold())

                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlimited card generation", systemImage: "infinity")
                    Label("Advanced scheduling", systemImage: "calendar.badge.clock")
                    Label("Priority updates", systemImage: "star.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .verbaCard()

                Button("Unlock Premium") {
                    _ = appState.redeem(code: "VERBADOC4FREE")
                    dismiss()
                }
                .buttonStyle(VerbaButtonStyle())

                Button("Redeem Code") {
                    showRedeem = true
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Premium")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showRedeem) {
                RedeemCodeView(appState: appState)
            }
        }
    }
}
