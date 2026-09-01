import Foundation
import CryptoKit
import Security

// MARK: - TLSPinningDelegate
//
// Verifies every HTTPS connection to api.groq.com against pinned public-key
// hashes (SPKI SHA-256). A MITM proxy cannot intercept even if the attacker
// installs a custom root CA on the device.
//
// ── Pin rotation procedure (ZERO-DOWNTIME) ──────────────────────────────────
//
//  When a cert is about to expire:
//
//  1. Get the new cert hash (run this ~4 weeks before expiry):
//
//       echo | openssl s_client -connect api.groq.com:443 -servername api.groq.com \
//         2>/dev/null | openssl x509 -pubkey -noout \
//         | openssl pkey -pubin -outform der \
//         | openssl dgst -sha256 -binary | base64
//
//  2. ADD the new pin to `activePins` alongside the old one (do NOT remove yet).
//     Set its expiry date. Ship an app update.
//
//  3. Wait ≥ 14 days for the update to propagate to your user base.
//
//  4. After the old cert expires AND update adoption is high enough,
//     REMOVE the old pin entry and ship another update.
//
//  This overlap window prevents users on the old app version from losing
//  connectivity when the cert rolls.
//
// ── Adding a new pin ────────────────────────────────────────────────────────
//  Append one `PinnedKey` entry to `activePins`. That's the only change needed.

final class TLSPinningDelegate: NSObject, URLSessionDelegate {

    static let shared = TLSPinningDelegate()
    private override init() {}

    // MARK: - Pin Registry

    struct PinnedKey {
        let name:    String    // human-readable label for logs
        let hash:    String    // SPKI SHA-256, base64
        let expires: String    // YYYY-MM-DD — informational only, not enforced at runtime
    }

    /// All currently trusted public-key hashes.
    ///
    /// The connection is accepted if ANY certificate in the chain matches ANY entry here.
    /// This means: add the NEXT pin before removing the CURRENT pin (see rotation guide above).
    ///
    /// ⚠️  EXPIRY ALERT:
    ///     api.groq.com leaf cert expires 2026-08-08.
    ///     Add the next leaf hash by 2026-07-10 and ship an update.
    ///     Set a calendar reminder: "Rotate Groq TLS pin" → 2026-07-10.
    private static let activePins: [PinnedKey] = [
        PinnedKey(
            name:    "api.groq.com leaf",
            hash:    "NSUwR6RBgH3a1fgXJYTEtVVUxeRgIIRwhID90KEv4Qc=",
            expires: "2026-08-08"
        ),
        PinnedKey(
            name:    "Google Trust Services WE1 intermediate",
            hash:    "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",
            expires: "2027-06-01"   // intermediate CAs rotate less often
        ),
        // ── Add next leaf pin here during rotation overlap window ──
        // PinnedKey(
        //     name:    "api.groq.com leaf (next)",
        //     hash:    "<new-base64-hash>",
        //     expires: "20XX-XX-XX"
        // ),
    ]

    // Pre-compute as a Set for O(1) lookup during the TLS handshake.
    private static let pinnedHashSet: Set<String> = Set(activePins.map { $0.hash })

    // MARK: - EC P-256 SPKI Header
    //
    // iOS's SecKeyCopyExternalRepresentation returns the raw 65-byte uncompressed
    // EC point (0x04 || x || y). To match OpenSSL's SubjectPublicKeyInfo hash we
    // prepend the 26-byte ASN.1 DER algorithm identifier for id-ecPublicKey / P-256.

    private static let ecP256SPKIHeader: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00
    ]

    // RSA-2048 header — kept for future-proofing if Groq switches key types.
    private static let rsa2048SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
        0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
        0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session:           URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler:   @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            // Non-certificate challenge (e.g. client auth) — reject.
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 1: Standard chain validation first.
        // We still require a trusted root; pinning is an additional check on top.
        var error: CFError?
        let chainValid = SecTrustEvaluateWithError(serverTrust, &error)
        guard chainValid else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 2: Check every certificate in the chain against our pinned hashes.
        // Pass if ANY cert in the chain matches — this handles both leaf and CA backup pins.
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        for cert in chain {
            if let hash = spkiHash(of: cert), Self.pinnedHashSet.contains(hash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No certificate in the chain matched a pinned hash — reject connection.
        #if DEBUG
        print("[TLSPin] ❌ Pin mismatch for \(challenge.protectionSpace.host). Check TLSPinningDelegate.activePins.")
        #endif
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - SPKI Hash Extraction

    private func spkiHash(of certificate: SecCertificate) -> String? {
        guard
            let publicKey  = SecCertificateCopyKey(certificate),
            let keyData    = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { return nil }

        let attrs = SecKeyCopyAttributes(publicKey) as? [CFString: Any]
        let keyType = attrs?[kSecAttrKeyType] as? String

        // Select the correct SPKI header for this key type/size.
        let header: [UInt8]
        if keyType == (kSecAttrKeyTypeEC as String) {
            guard keyData.count == 65 else { return nil }   // EC P-256 uncompressed point
            header = Self.ecP256SPKIHeader
        } else if keyType == (kSecAttrKeyTypeRSA as String) {
            header = keyData.count > 300 ? [] : Self.rsa2048SPKIHeader
        } else {
            return nil  // Unknown key type — fail safe
        }

        var spki = Data(header)
        spki.append(keyData)

        let hash = SHA256.hash(data: spki)
        return Data(hash).base64EncodedString()
    }
}
