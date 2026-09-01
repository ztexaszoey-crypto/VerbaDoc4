import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var isSignUp        = false
    @State private var email           = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var isLoading       = false
    @State private var errorMessage: String? = nil
    @State private var showForgotPassword    = false
    @State private var resetEmail      = ""
    @State private var resetSent       = false

    var body: some View {
        ZStack {
            VerbaTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 10) {
                        VerbaMascot(mood: .happy, size: 72)
                            .padding(.top, 64)
                        Text("VerbaDoc")
                            .font(VerbaFont.serif(size: 34))
                            .foregroundStyle(VerbaTheme.ink)
                        Text(isSignUp ? "create your account" : "welcome back")
                            .font(VerbaFont.syne(.regular, size: 15))
                            .foregroundStyle(VerbaTheme.muted)
                    }
                    .padding(.bottom, 40)

                    // ── Form ──────────────────────────────────────────────
                    VStack(spacing: 13) {
                        LoginTextField(placeholder: "email", text: $email,
                                       keyboardType: .emailAddress)

                        LoginSecureField(placeholder: "password", text: $password)

                        if isSignUp {
                            LoginSecureField(placeholder: "confirm password",
                                            text: $confirmPassword)
                        }

                        if !isSignUp {
                            Button("forgot password?") { showForgotPassword = true }
                                .font(VerbaFont.syne(.regular, size: 13))
                                .foregroundStyle(VerbaTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(VerbaFont.syne(.regular, size: 13))
                                .foregroundStyle(.red.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        }

                        // Primary CTA
                        Button { Task { await submit() } } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(VerbaTheme.green)
                                    .frame(height: 52)
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(isSignUp ? "create account" : "log in")
                                        .font(VerbaFont.syne(.regular, size: 16))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(isLoading)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 28)

                    // ── Divider ───────────────────────────────────────────
                    HStack(spacing: 12) {
                        Rectangle().fill(VerbaTheme.border).frame(height: 1)
                        Text("or")
                            .font(VerbaFont.syne(.regular, size: 13))
                            .foregroundStyle(VerbaTheme.muted)
                        Rectangle().fill(VerbaTheme.border).frame(height: 1)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)

                    // ── Social Buttons ────────────────────────────────────
                    VStack(spacing: 12) {
                        // Google
                        Button { Task { await googleSignIn() } } label: {
                            HStack(spacing: 10) {
                                Text("G")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                                Text("continue with Google")
                                    .font(VerbaFont.syne(.regular, size: 15))
                                    .foregroundStyle(VerbaTheme.ink)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(VerbaTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(VerbaTheme.border, lineWidth: 1)
                            )
                        }

                        // Apple
                        SignInWithAppleButton(.signIn) { request in
                            authManager.prepareAppleRequest(request)
                        } onCompletion: { result in
                            Task {
                                do { try await authManager.handleAppleResult(result) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 28)

                    // ── Toggle ────────────────────────────────────────────
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isSignUp.toggle() }
                        errorMessage = nil
                    } label: {
                        Text(isSignUp
                             ? "already have an account? log in"
                             : "don't have an account? sign up")
                            .font(VerbaFont.syne(.regular, size: 14))
                            .foregroundStyle(VerbaTheme.green)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 48)
                }
            }
        }
        .sheet(isPresented: $showForgotPassword) { forgotPasswordSheet }
    }

    // MARK: - Forgot Password Sheet

    private var forgotPasswordSheet: some View {
        NavigationStack {
            ZStack {
                VerbaTheme.bg.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("reset password")
                        .font(VerbaFont.serif(size: 24))
                        .foregroundStyle(VerbaTheme.ink)
                        .padding(.top, 32)

                    if resetSent {
                        VStack(spacing: 10) {
                            Image(systemName: "envelope.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(VerbaTheme.green)
                            Text("check your email!")
                                .font(VerbaFont.syne(.regular, size: 17))
                                .foregroundStyle(VerbaTheme.ink)
                            Text("a reset link was sent to \(resetEmail)")
                                .font(VerbaFont.syne(.regular, size: 14))
                                .foregroundStyle(VerbaTheme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 28)
                    } else {
                        LoginTextField(placeholder: "your email", text: $resetEmail,
                                       keyboardType: .emailAddress)
                            .padding(.horizontal, 28)

                        Button {
                            Task {
                                try? await authManager.resetPassword(email: resetEmail)
                                resetSent = true
                            }
                        } label: {
                            Text("send reset link")
                                .font(VerbaFont.syne(.regular, size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(VerbaTheme.green)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.horizontal, 28)
                    }
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { showForgotPassword = false }
                        .foregroundStyle(VerbaTheme.green)
                }
            }
        }
    }

    // MARK: - Actions

    private func submit() async {
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "please fill in all fields"; return
        }
        if isSignUp && password != confirmPassword {
            errorMessage = "passwords don't match"; return
        }
        if isSignUp && password.count < 6 {
            errorMessage = "password must be at least 6 characters"; return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if isSignUp { try await authManager.signUp(email: email, password: password) }
            else        { try await authManager.signIn(email: email, password: password) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func googleSignIn() async {
        do { try await authManager.signInWithGoogle() }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Reusable Fields

private struct LoginTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .font(VerbaFont.syne(.regular, size: 15))
            .foregroundStyle(VerbaTheme.ink)
            .tint(VerbaTheme.green)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(VerbaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VerbaTheme.border, lineWidth: 1)
            )
    }
}

private struct LoginSecureField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isVisible = false

    var body: some View {
        HStack {
            Group {
                if isVisible {
                    TextField(placeholder, text: $text).autocapitalization(.none)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .autocorrectionDisabled()
            .font(VerbaFont.syne(.regular, size: 15))
            .foregroundStyle(VerbaTheme.ink)
            .tint(VerbaTheme.green)

            Button { isVisible.toggle() } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(VerbaTheme.muted)
                    .font(.system(size: 15))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(VerbaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VerbaTheme.border, lineWidth: 1)
        )
    }
}
