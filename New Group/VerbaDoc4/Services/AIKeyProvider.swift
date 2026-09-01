import Foundation

// MARK: - AIKeyProvider
//
// Protocol that decouples key delivery from the AI call site.
//
// Current implementation: KeychainKeyProvider — reads keys from the Keychain
// (seeded from Secrets._bootstrapKeys at first launch).
//
// Migration path to a server proxy (no client-side keys):
//   1. Implement ProxyKeyProvider conforming to AIKeyProvider.
//      ProxyKeyProvider.nextKey() calls your backend (Cloudflare Worker,
//      Lambda, etc.) which holds the real keys and returns a short-lived token.
//   2. Swap one line in GroqAPI.init():
//         keyProvider = ProxyKeyProvider(endpoint: URL(string: "https://api.yourdomain.com/token")!)
//   3. Update TLSPinningDelegate to also pin your proxy domain.
//   4. Empty Secrets._bootstrapKeys and stop shipping keys in the binary.
//
// No other files need to change for the migration.

protocol AIKeyProvider: AnyObject {
    /// Returns the next API key to use, rotating through the pool.
    /// Returns nil when no keys are available (all exhausted or empty pool).
    func nextKey() -> String?

    /// Returns all available keys (used to size rate limiter / circuit breaker pools).
    var allKeys: [String] { get }

    /// Refreshes the key pool (called when pool is found empty at call time).
    func refresh()
}

// MARK: - KeychainKeyProvider (current implementation)

final class KeychainKeyProvider: AIKeyProvider {
    static let shared = KeychainKeyProvider()
    private init() {}

    private var _keys: [String] = []
    private var _cursor: Int = 0
    private let lock = NSLock()

    var allKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        if _keys.isEmpty { _load() }
        return _keys
    }

    func nextKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        if _keys.isEmpty { _load() }
        guard !_keys.isEmpty else { return nil }
        let key = _keys[_cursor % _keys.count]
        _cursor = (_cursor + 1) % _keys.count
        return key
    }

    func refresh() {
        lock.lock(); defer { lock.unlock() }
        _load()
    }

    // Call inside lock only.
    private func _load() {
        _keys = SecureKeyStore.shared.apiKeys.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
            && ($0.hasPrefix("gsk_") || $0.hasPrefix("vd_"))
        }
        _cursor = 0
    }
}
