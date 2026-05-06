import SwiftUI

struct RedeemCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var code = ""
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Code") {
                    TextField("Enter code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let msg = successMessage {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(VerbaTheme.success)
                    }
                } else if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Redeem Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyCode() }
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func applyCode() {
        errorMessage = nil
        successMessage = nil
        switch appState.redeem(code: code) {
        case .success(let reward):
            successMessage = "Unlocked: \(reward)"
            HapticManager.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        case .alreadyUnlocked:
            errorMessage = "Already unlocked."
            HapticManager.impact()
        case .invalid:
            errorMessage = "Invalid code."
            HapticManager.impact()
        }
    }
}

