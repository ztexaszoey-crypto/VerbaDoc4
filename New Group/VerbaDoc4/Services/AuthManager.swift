import Foundation
import FirebaseAuth
import GoogleSignIn
import FirebaseCore
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var currentUser: User? = nil
    @Published private(set) var isLoading = true

    private var currentNonce: String?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isLoading = false
            }
        }
    }

    var isLoggedIn: Bool { currentUser != nil }
    var userEmail: String? { currentUser?.email }

    // MARK: - Email / Password

    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        currentUser = result.user
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        currentUser = result.user
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - Google

    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        currentUser = authResult.user
    }

    // MARK: - Apple (split for SwiftUI SignInWithAppleButton)

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async throws {
        let authorization = try result.get()
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let appleIDToken = appleIDCredential.identityToken,
            let idTokenString = String(data: appleIDToken, encoding: .utf8),
            let nonce = currentNonce
        else { throw AuthError.missingToken }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        currentUser = authResult.user
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
        currentUser = nil
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case missingClientID, noRootViewController, missingToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:      return "Google Sign-In is not configured."
        case .noRootViewController: return "Unable to present sign-in screen."
        case .missingToken:         return "Authentication token is missing."
        }
    }
}
