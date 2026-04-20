import SwiftUI

struct PaywallView: View {
    @State private var showRedeem = false

    var body: some View {
        VStack(spacing: 20) {
            Text("VerbaDoc Pro")
                .font(.largeTitle.bold())

            Text("Unlimited materials and advanced study tools.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Start Trial") {}
                .buttonStyle(VerbaButtonStyle())

            Button("Redeem Code") {
                showRedeem = true
            }
            .buttonStyle(VerbaButtonStyle(filled: false))
        }
        .padding()
        .navigationTitle("Upgrade")
        .sheet(isPresented: $showRedeem) {
            RedeemCodeView()
        }
    }
}

#Preview {
    NavigationStack { PaywallView() }
}
