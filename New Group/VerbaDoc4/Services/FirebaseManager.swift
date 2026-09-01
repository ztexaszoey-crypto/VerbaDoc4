import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - FirebaseManager
//
// Handles Firestore real-time messaging and user profile setup.
// Auth is now managed by AuthManager. FirebaseManager listens for Auth state
// changes and calls configure(with:) automatically when a user logs in.
//
// Data model:
//   /users/{uid}             { displayName, friendCode }
//   /conversations/{convId}  (convId = sorted UIDs joined by "_")
//     /messages/{msgId}      { senderUID, senderName, text, timestamp }

@MainActor
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    // MARK: - Published

    @Published private(set) var isReady       = false
    @Published private(set) var myUID         = ""
    @Published private(set) var myFriendCode  = ""

    // MARK: - Firestore

    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        // Automatically configure when Auth state changes (login/logout).
        // Store the handle so the listener can be removed if needed.
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user {
                    self?.configure(with: user)
                } else {
                    self?.isReady      = false
                    self?.myUID        = ""
                    self?.myFriendCode = ""
                }
            }
        }
    }

    // MARK: - Setup

    private func configure(with user: User) {
        myUID        = user.uid
        myFriendCode = String(user.uid.prefix(6)).uppercased()
        isReady      = true
        // Write/update the user document so others can look us up by friend code
        let displayName = UserDefaults.standard.string(forKey: "profile.name") ?? ""
        db.collection("users").document(user.uid).setData([
            "displayName": displayName.isEmpty ? "student" : displayName,
            "friendCode" : myFriendCode
        ], merge: true)
    }

    // MARK: - Friend Lookup

    /// Finds a user by their 6-character friend code. Returns their UID or nil.
    func findUser(byCode code: String) async -> (uid: String, name: String)? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 6 else { return nil }
        do {
            let snap = try await db.collection("users")
                .whereField("friendCode", isEqualTo: normalized)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first else { return nil }
            let name = doc.data()["displayName"] as? String ?? "student"
            return (uid: doc.documentID, name: name)
        } catch {
            #if DEBUG
            print("[Firebase] Friend lookup failed: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Conversation ID

    /// Deterministic conversation ID — same result regardless of who initiates.
    func conversationID(with otherUID: String) -> String {
        [myUID, otherUID].sorted().joined(separator: "_")
    }

    // MARK: - Send Message

    func send(text: String, to convID: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let displayName = UserDefaults.standard.string(forKey: "profile.name") ?? "student"
        do {
            try await db.collection("conversations")
                .document(convID)
                .collection("messages")
                .addDocument(data: [
                    "senderUID"  : myUID,
                    "senderName" : displayName.isEmpty ? "student" : displayName,
                    "text"       : text.trimmingCharacters(in: .whitespacesAndNewlines),
                    "timestamp"  : FieldValue.serverTimestamp()
                ])
        } catch {
            #if DEBUG
            print("[Firebase] Send failed: \(error)")
            #endif
        }
    }

    // MARK: - Listen to Messages

    /// Attaches a real-time listener. Returns a detach closure — call it on disappear.
    func listenToMessages(
        in convID: String,
        onChange: @escaping ([DMMessage]) -> Void
    ) -> ListenerRegistration {
        db.collection("conversations")
            .document(convID)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                let messages = snap.documents.compactMap { DMMessage(document: $0) }
                Task { @MainActor in onChange(messages) }
            }
    }
}

// MARK: - DMMessage

struct DMMessage: Identifiable {
    let id         : String
    let senderUID  : String
    let senderName : String
    let text       : String
    let timestamp  : Date

    @MainActor var isFromMe: Bool { senderUID == FirebaseManager.shared.myUID }

    init?(document: QueryDocumentSnapshot) {
        guard
            let text      = document.data()["text"]      as? String,
            let senderUID = document.data()["senderUID"] as? String
        else { return nil }
        self.id         = document.documentID
        self.senderUID  = senderUID
        self.senderName = document.data()["senderName"] as? String ?? "student"
        self.text       = text
        // Firestore Timestamp → Date; fall back to now if not yet committed
        if let ts = document.data()["timestamp"] as? Timestamp {
            self.timestamp = ts.dateValue()
        } else {
            self.timestamp = Date()
        }
    }
}
