import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - SignInView (Phase 6 — cozy toy-block matte 3D)
//
// Email + password sign-in / sign-up screen wrapped in `CozyBackdrop`
// (solid matcha), the form rendered as a `cozyBlockCard()` (sage
// chassis + 4pt forest stroke), chunky pill text fields using the
// cozy palette inline, Apple button framed in a sage chip with
// forest border, and the submit / toggle CTA using
// `cozyBlockButtonStyle()`. Inline `ForgotPasswordSheet` gets the
// same cozy treatment. All glassmorphic / pastel-gradient decorations
// have been removed per Phase 6 brief.

struct SignInView: View {

    @StateObject private var auth = AuthService.shared

    @State private var email         = ""
    @State private var password      = ""
    @State private var isSignUp      = false
    @State private var errorMessage: String? = nil
    @State private var showPassword  = false
    @State private var isAppleLoading = false
    @State private var currentNonce: String = ""

    @State private var showForgotPassword = false

    var body: some View {
        CozyBackdrop {
            ScrollView {
                VStack(spacing: 0) {

                    hero
                        .padding(.bottom, 32)

                    formCard

                    freeTierNote
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)

                    Spacer(minLength: 60)
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(prefillEmail: email)
        }
    }

    // MARK: - Hero (mascot + wordmark in cream chip)

    private var hero: some View {
        VStack(spacing: 14) {
            VerbaMascot(mood: .happy, size: 76)
                .padding(14)
                .background(
                    ZStack {
                        Circle().fill(VerbaTheme.glossCream)
                        Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2.5)
                    }
                )
                .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                        radius: 0, x: 0, y: 6)
                .shadow(color: VerbaTheme.glossCream.opacity(0.40),
                        radius: 14, x: 0, y: 4)
                .padding(.top, 36)

            VStack(spacing: 4) {
                Text("VerbaDoc")
                    .font(VerbaFont.title(size: 32, weight: .black))
                    .foregroundStyle(VerbaTheme.cozyForest)

                Text(isSignUp ? "create a free account" : "welcome back")
                    .font(VerbaFont.bodyRounded(size: 15, weight: .medium))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            }
        }
    }

    // MARK: - Form card (sticky-note pastel chassis)

    private var formCard: some View {
        VStack(spacing: 14) {

            if let msg = errorMessage {
                errorBanner(msg)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("email")
                pastelTextField(
                    text:           $email,
                    placeholder:    "you@example.com",
                    isSecure:       false,
                    keyboard:       .emailAddress,
                    contentType:    .emailAddress,
                    autoCapitalize: false
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fieldLabel("password")
                    Spacer()
                    if !isSignUp {
                        Button("forgot?") { showForgotPassword = true }
                            .font(VerbaFont.syne(.bold, size: 12))
                            .tracking(0.4)
                            .foregroundStyle(VerbaTheme.cozyForest)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(VerbaTheme.glossCream.opacity(0.85))
                            )
                            .overlay(
                                Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.5)
                            )
                    }
                }
                passwordField
            }

            // Submit — chunky 3D primary
            Button {
                Task { await submit() }
            } label: {
                ZStack {
                    if auth.isLoading {
                        ProgressView().tint(VerbaTheme.darkOliveInk)
                    } else {
                        Text(isSignUp ? "create account" : "sign in")
                            .font(VerbaFont.syne(.bold, size: 17))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    }
                }
            }
            .cozyBlockButtonStyle()
            .disabled(auth.isLoading || email.isEmpty || password.isEmpty)
            .opacity((auth.isLoading || email.isEmpty || password.isEmpty) ? 0.55 : 1)

            HStack(spacing: 12) {
                Rectangle().fill(VerbaTheme.oliveBorder.opacity(0.45)).frame(height: 1.5)
                Text("or")
                    .font(VerbaFont.syne(.semibold, size: 12))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                Rectangle().fill(VerbaTheme.oliveBorder.opacity(0.45)).frame(height: 1.5)
            }

            // Apple button — wrapped in cream chip + olive border
            appleChip

            // Toggle sign-in / sign-up
            Button {
                withAnimation(.verba) {
                    isSignUp.toggle()
                    errorMessage = nil
                }
            } label: {
                Text(isSignUp ? "already have an account? sign in" : "no account? create one free")
                    .font(VerbaFont.syne(.semibold, size: 13))
                    .foregroundStyle(VerbaTheme.cozyForest)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 22)
                    .background(Capsule().fill(VerbaTheme.cozySage))
                    .overlay(Capsule().stroke(VerbaTheme.cozyForest, lineWidth: VerbaTheme.cozyStroke))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)            .frame(maxWidth: .infinity)
            .cozyBlockCard(fill: VerbaTheme.cozySage)
            .padding(.horizontal, 18)
    }

    // MARK: - Password row (textfield + toggle eye, in cream chip)

    private var passwordField: some View {
        HStack {
            Group {
                if showPassword {
                    TextField("••••••••", text: $password)
                } else {
                    SecureField("••••••••", text: $password)
                }
            }
            .textContentType(isSignUp ? .newPassword : .password)
            .font(VerbaFont.syne(.regular, size: 15))
            .foregroundStyle(VerbaTheme.cozyForest)
            .autocorrectionDisabled()

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .fill(VerbaTheme.glossCream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .inset(by: 2)
                .stroke(VerbaTheme.glossCream.opacity(0.65), lineWidth: 1.2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                radius: 0, x: 0, y: 3)
    }

    // MARK: - Apple Sign-In chip (cream wrap around ASAuthorizationAppleIDButton)

    private var appleChip: some View {
        ZStack {
            SignInWithAppleButton(
                isSignUp ? .signUp : .signIn,
                onRequest: { request in
                    let rawNonce = randomNonceString()
                    currentNonce = rawNonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = sha256(rawNonce)
                },
                onCompletion: { result in
                    Task { await handleAppleSignIn(result) }
                }
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .allowsHitTesting(!isAppleLoading)

            if isAppleLoading {
                RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 52)
                ProgressView().tint(VerbaTheme.darkOliveInk)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .fill(VerbaTheme.glossCream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                radius: 0, x: 0, y: 3)
    }

    // MARK: - Field label (uppercase tracked caption)

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VerbaFont.syne(.bold, size: 11))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(VerbaTheme.cozyOliveSubtext)
            .padding(.leading, 4)
    }

    // MARK: - Error banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VerbaTheme.cozyForest)
            Text(msg)
                .font(VerbaFont.syne(.semibold, size: 13))
                .foregroundStyle(VerbaTheme.cozyForest)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .fill(VerbaTheme.yellow.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
        )
    }

    // MARK: - Free tier note

    private var freeTierNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(VerbaTheme.cozyForest)
                .frame(width: 26, height: 26)
                .background(Circle().fill(VerbaTheme.glossCream))
                .overlay(Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 1.5))
            Text("Free plan: \(ProGate.Limit.maxAIGenerations) AI card generations total · Upgrade anytime for unlimited access")
                .font(VerbaFont.syne(.medium, size: 12))
                .foregroundStyle(VerbaTheme.cozyOliveSubtext)
        }
    }

    // MARK: - Email/password submit

    private func submit() async {
        errorMessage = nil

        // SECURITY (Ian Lackey gap #6): throttle FIRST so the gate
        // applies uniformly regardless of input validity. A scripted
        // credential-stuffing loop with valid-format input still
        // burns the per-minute token; an honest typo doesn't burn
        // a token (which would be a worse UX trade).
        guard RateLimiter.consume(.authAttempt) else {
            errorMessage = "Too many attempts. Wait a minute and try again."
            return
        }

        let trimmedEmail    = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password

        // SECURITY: tight email regex (RFC-5322-lite) — prevents
        // `contains("@")` loophole that accepted "abc@" or "@".
        guard Self.isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard trimmedPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        do {
            if isSignUp {
                try await AuthService.shared.signUp(email: trimmedEmail, password: trimmedPassword)
            } else {
                try await AuthService.shared.signIn(email: trimmedEmail, password: trimmedPassword)
            }
        } catch let e as AuthService.AuthError {
            errorMessage = e.errorDescription
        } catch {
            // SECURITY: never leak `error.localizedDescription` to UI.
            errorMessage = FriendlyErrorMapper.message(for: error, in: .auth)
        }
    }

    /// RFC-5322-lite email regex. Accepts the 99% of valid emails
    /// without leaking server-side validation rules. Good enough for
    /// pre-submit client-side rejection; Supabase enforces the rest.
    private static func isValidEmail(_ s: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Apple Sign In helpers

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isAppleLoading = true
        defer { isAppleLoading = false }
        errorMessage = nil

        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                await MainActor.run {
                    // SECURITY: user-facing copy from FriendlyErrorMapper.
                    // Never leak the ASAuthorization raw error code or
                    // the underlying Domain detail to user.
                    errorMessage = FriendlyErrorMapper.message(for: error, in: .auth)
                }
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                await MainActor.run {
                    errorMessage = "Apple Sign In failed: could not read identity token."
                }
                return
            }

            do {
                try await AuthService.shared.signInWithApple(identityToken: identityToken, nonce: currentNonce)
            } catch {
                await MainActor.run {
                    // SECURITY: user-facing copy from FriendlyErrorMapper.
                    errorMessage = FriendlyErrorMapper.message(for: error, in: .auth)
                }
            }
        }
    }
}

// MARK: - pastelTextField (cream chunky text field, dark olive border)
//
// Drop-in replacement for SwiftUI `TextField`/SecureField that respects
// the pastel system. Lives in Auth/ for now; if other views need it,
// promote to Design/PastelTextField.swift.

func pastelTextField(
    text:           Binding<String>,
    placeholder:    String,
    isSecure:       Bool = false,
    keyboard:       UIKeyboardType = .default,
    contentType:    UITextContentType? = nil,
    autoCapitalize: Bool            = true
) -> some View {
    Group {
        if isSecure {
            SecureField(placeholder, text: text)
        } else {
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
        }
    }
    .textContentType(contentType)
    .autocapitalization(autoCapitalize ? .sentences : .none)
    .autocorrectionDisabled(true)
    .font(VerbaFont.syne(.regular, size: 15))
    .foregroundStyle(VerbaTheme.cozyForest)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(
        RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
            .fill(VerbaTheme.cozySage)
    )
    .overlay(
        RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
            .stroke(VerbaTheme.cozyForest, lineWidth: 4)
    )
}

// MARK: - ForgotPasswordSheet (FELIwS pastel-green migration)
//
// Same treatment as SignInView: cream sticker card, pastel chunky text
// field, pastel primary CTA, success state with capybara headline.

struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let prefillEmail: String

    @State private var email      = ""
    @State private var isSending  = false
    @State private var didSend    = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            CozyBackdrop {
                VStack(spacing: 20) {
                    if didSend {
                        successState
                    } else {
                        inputState
                    }
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { dismiss() }
                        .font(VerbaFont.syne(.bold, size: 12))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(VerbaTheme.cozyForest)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(VerbaTheme.glossCream))
                        .overlay(Capsule().stroke(VerbaTheme.oliveBorder, lineWidth: 1.5))
                        .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.18),
                                radius: 0, x: 0, y: 3)
                }
            }
        }
        .onAppear {
            if email.isEmpty {
                email = prefillEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private var inputState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("enter your email and we'll send a reset link.")
                .font(VerbaFont.bodyRounded(size: 14, weight: .medium))
                .foregroundStyle(VerbaTheme.cozyForest)
                .padding(.horizontal, 4)

            if let msg = errorMsg {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Text(msg)
                        .font(VerbaFont.syne(.semibold, size: 13))
                        .foregroundStyle(VerbaTheme.cozyForest)
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                        .fill(VerbaTheme.yellow.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VerbaTheme.r16, style: .continuous)
                        .stroke(VerbaTheme.oliveBorder, lineWidth: 2)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("email")
                    .font(VerbaFont.syne(.bold, size: 11))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .padding(.leading, 4)
                pastelTextField(
                    text:           $email,
                    placeholder:    "you@example.com",
                    isSecure:       false,
                    keyboard:       .emailAddress,
                    contentType:    .emailAddress,
                    autoCapitalize: false
                )
            }

            Button {
                Task { await sendReset() }
            } label: {
                ZStack {
                    if isSending {
                        ProgressView().tint(VerbaTheme.darkOliveInk)
                    } else {
                        Text("send reset link")
                            .font(VerbaFont.syne(.bold, size: 16))
                            .foregroundStyle(VerbaTheme.cozyForest)
                    }
                }
            }
            .cozyBlockButtonStyle()
            .disabled(isSending || email.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(isSending || email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .cozyBlockCard(fill: VerbaTheme.cozySage)
        .padding(.horizontal, 16)
    }

    private var successState: some View {
        VStack(spacing: 18) {
            VerbaMascot(mood: .happy, size: 80)
                .padding(14)
                .background(
                    ZStack {
                        Circle().fill(VerbaTheme.glossCream)
                        Circle().stroke(VerbaTheme.oliveBorder, lineWidth: 2.5)
                    }
                )
                .shadow(color: VerbaTheme.oliveContactShadow.opacity(0.30),
                        radius: 0, x: 0, y: 6)

            VStack(spacing: 8) {
                Text("check your inbox")
                    .font(VerbaFont.title(size: 24, weight: .black))
                    .foregroundStyle(VerbaTheme.cozyForest)
                Text("If an account exists for **\(email)**, a reset link has been sent. Check your spam folder if you don't see it.")
                    .font(VerbaFont.bodyRounded(size: 14, weight: .medium))
                    .foregroundStyle(VerbaTheme.cozyOliveSubtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .cozyBlockCard(fill: VerbaTheme.cozySage)
            }
        }
        .padding(.horizontal, 24)
    }

    private func sendReset() async {
        errorMsg = nil
        isSending = true
        defer { isSending = false }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        // SECURITY: throttle FIRST (uniform enforcement) — see the
        // SignInView.submit() comment for the trade-off rationale.
        guard RateLimiter.consume(.authAttempt) else {
            errorMsg = "Too many attempts. Wait a minute and try again."
            return
        }

        // SECURITY: tight regex match — `contains("@")` would accept
        // strings like "@" or "abc@".
        guard trimmed.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            errorMsg = "Please enter a valid email address."
            return
        }

        do {
            try await AuthService.shared.resetPassword(email: trimmed)
            await MainActor.run { didSend = true }
        } catch {
            await MainActor.run {
                errorMsg = "Couldn't send reset email. Check your connection and try again."
            }
        }
    }
}

