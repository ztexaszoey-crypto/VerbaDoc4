import SwiftUI

struct RedeemCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var redeemed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Enter code", text: $code)
                if redeemed {
                    Label("Code accepted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .navigationTitle("Redeem Code")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Redeem") { redeemed = !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                }
            }
        }
    }
}

#Preview {
    RedeemCodeView()
}
