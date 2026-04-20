import SwiftUI

struct RedeemCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState

    @State private var code = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Code") {
                    TextField("Enter code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if showError {
                    Text("Invalid code")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Redeem")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if appState.redeem(code: code) {
                            dismiss()
                        } else {
                            showError = true
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
