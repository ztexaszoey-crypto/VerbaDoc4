import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - FirestoreKeyProvider
//
// Fetches Groq API keys from a server-side Firestore document instead of
// compiling them into the app binary. Keys are stored in /config/apiKeys
// (readable by authenticated users only; writable only via Firebase Admin SDK
// or the Firebase Console — never from the client app).
//
// Firestore path: /config/apiKeys
// Required document structure:
//   { "groq": ["gsk_xxx", "gsk_yyy"] }
//
// Required Firestore rule (add to firestore.rules — already done):
//   match /config/{doc} {
//     allow read: if request.auth != null;
//     allow write: if false;
//   }
//
// Key rotation procedure (no app update needed):
//   1. Add new key(s) to /config/apiKeys.groq in Firebase Console.
//   2. Revoke old key(s) in Groq dashboard.
//   3. Remove old key(s) from /config/apiKeys.groq.
//   Users get the new keys on next app launch or next AI request.
//
// Offline behaviour:
//   Keys fetched from Firestore are cached in the Keychain immediately.
//   On subsequent launches without network, the Keychain cache is used as a
//   fallback so AI features remain available.
//
// ── Migration from binary keys ───────────────────────────────────────────────
//   1. Add keys to /config/apiKeys in Firebase Console.
//   2. Secrets._bootstrapKeys is now empty — no keys are compiled into binary.
//   3. Existing devices with keys in Keychain from prior builds continue to work
//      until FirestoreKeyProvider.fetchKeys() runs and refreshes the cache.
//   4. This is the "acceptable TestFlight" solution described in AIKeyProvider.swift.
//      For production at scale, implement the ProxyKeyProvider (server-side proxy).

final class FirestoreKeyProvider: AIKeyProvider {
    static let shared = FirestoreKeyProvider()
    private init() {}

    private let db = Firestore.firestore()
    private var _keys: [String] = []
    private var _cursor: Int = 0
    private let lock = NSLock()

    // MARK: - AIKeyProvider

    var allKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        if _keys.isEmpty { _loadFromKeychain() }
        return _keys
    }

    func nextKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        if _keys.isEmpty { _loadFromKeychain() }
        guard !_keys.isEmpty else { return nil }
        let key = _keys[_cursor % _keys.count]
        _cursor = (_cursor + 1) % _keys.count
        return key
    }

    /// Called by GroqAPI's lazy-refresh path when the in-memory pool is empty.
    /// Loads from Keychain immediately (synchronous fallback) and kicks off a
    /// background Firestore fetch to replenish the cache.
    func refresh() {
        lock.lock()
        _loadFromKeychain()
        lock.unlock()
        Task { await fetchKeys() }
    }

    // MARK: - Primary Fetch (call after authentication resolves)

    /// Fetches fresh keys from /config/apiKeys and caches them to the Keychain.
    /// No-ops if the user is not authenticated (Firestore rules would reject anyway).
    func fetchKeys() async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            let doc = try await db
                .collection("config")
                .document("apiKeys")
                .getDocument()

            guard let remoteKeys = doc.data()?["groq"] as? [String] else {
                // Document exists but no groq key — leave current cache intact.
                print("[FirestoreKeyProvider] ⚠️ /config/apiKeys has no 'groq' field.")
                return
            }

            let validated = remoteKeys.filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.hasPrefix("gsk_")
            }
            guard !validated.isEmpty else {
                print("[FirestoreKeyProvider] ⚠️ /config/apiKeys.groq is empty.")
                return
            }

            // Update in-memory pool via a synchronous helper.
            // NSLock.lock() must not be called directly inside an async function
            // body (Swift 6 error; Swift 5 warning). Delegating to a non-async
            // method moves the lock call out of the async execution context.
            _applyValidatedKeys(validated)

            // Write to Keychain so next offline launch uses fresh keys.
            try? SecureKeyStore.shared.replaceKeys(validated)
            print("[FirestoreKeyProvider] ✓ Loaded \(validated.count) key(s) from Firestore.")

        } catch {
            // Network error, permission error, or Firestore offline.
            // Fall back to whatever is cached in the Keychain.
            print("[FirestoreKeyProvider] ⚠️ Fetch failed — using Keychain cache. Error: \(error.localizedDescription)")
            _applyKeychainFallback()
        }
    }

    // Non-async helper: NSLock is safe to use here (no async context).
    private func _applyValidatedKeys(_ keys: [String]) {
        lock.lock()
        _keys   = keys
        _cursor = 0
        lock.unlock()
    }

    // Non-async helper: NSLock is safe to use here.
    private func _applyKeychainFallback() {
        lock.lock()
        _loadFromKeychain()
        lock.unlock()
    }

    // MARK: - Private

    /// Loads keys from the Keychain. Must be called inside `lock`.
    private func _loadFromKeychain() {
        let cached = SecureKeyStore.shared.apiKeys
        if !cached.isEmpty {
            _keys   = cached
            _cursor = 0
        }
    }
}
