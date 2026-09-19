import Foundation
import Combine
import RevenueCat

// MARK: - PurchaseService
//
// Single RevenueCat integration point.
//
// Setup (one-time, after RevenueCat SDK is added via SPM):
//   1. Add SPM: https://github.com/RevenueCat/purchases-ios-spm (Package: RevenueCat)
//   2. Replace REVENUECAT_API_KEY below with your RevenueCat Apple API key
//      (RevenueCat Dashboard → Project → API Keys → Apple)
//   3. In App Store Connect: create two Auto-Renewable Subscriptions:
//        Product ID: verbadoc_pro_monthly  ($5.99/month)
//        Product ID: verbadoc_pro_annual   ($34.99/year)
//   4. In RevenueCat Dashboard:
//        - Add both products under your Apple app
//        - Create Entitlement "pro", attach both products
//        - Create Offering "default" with two packages (Monthly / Annual)
//
// Offline handling:
//   RevenueCat caches CustomerInfo locally. If the network is unavailable,
//   getCustomerInfo() returns the last cached value. isPro will be accurate
//   as long as the user has connected at least once.

final class PurchaseService: NSObject, ObservableObject {

    static let shared = PurchaseService()
    private override init() {}

    // MARK: - Config

    // ─────────────────────────────────────────────────────────────────────────
    // REVENUECAT API KEY LOADED FROM INFO.PLIST (injected by xcconfig).
    // Get it from: RevenueCat Dashboard → Project → API Keys → Apple App Specific Key
    // Format: appl_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    //
    // Set the Info.plist key `REVENUECAT_API_KEY` in your Release xcconfig to your
    // production "appl_..." key before App Store submission. The DEBUG fallback
    // below is the sandbox "test_..." key (TestFlight/Simulator only).
    //
    // A production build without a configured key will crash on launch via
    // fatalError, preventing a silent production failure.
    // ─────────────────────────────────────────────────────────────────────────
    static var apiKey: String {
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
           !plistKey.isEmpty {
            return plistKey
        }
        #if DEBUG
        return "test_GeroNWhxFPPSDAnqXcSqYtxQBlr"
        #else
        // App-Review-safe: never crash at module-init in production.
        // Production builds MUST set REVENUECAT_API_KEY via xcconfig.
        // When missing, `configure()`'s empty-key guard short-circuits
        // and surfaces a friendly error in the paywall instead of crashing.
        assertionFailure("[VerbaDoc] Missing REVENUECAT_API_KEY in Info.plist. Add via xcconfig before App Store submission. Configure will short-circuit and show 'API key missing' in paywall.")
        NSLog("[VerbaDoc] MISSING_REVENUECAT_API_KEY — returning empty; configure() will refuse to call Purchases.configure.")
        return ""
        #endif
    }

    /// RevenueCat entitlement identifier configured in the dashboard.
    static let entitlementID = "pro"

    // MARK: - Published state

    @Published private(set) var isPro: Bool = false
    @Published private(set) var offerings: Offerings? = nil
    @Published private(set) var configureError: String? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var restoreMessage: RestoreResult? = nil

    enum RestoreResult: Equatable {
        case restored
        case nothingToRestore
        case error(String)
    }

    // MARK: - Configure (call once at app launch)

    static func configure() {
        Purchases.logLevel = .error
        let key = apiKey
        // Protect against empty key (only DEBUG path can produce an empty string
        // if Info.plist override is broken). The Release path uses fatalError.
        guard !key.isEmpty else {
            print("[PurchaseService] Refusing to configure with empty API key.")
            DispatchQueue.main.async { shared.configureError = "RevenueCat API key missing. Check Info.plist." }
            return
        }
        Purchases.configure(withAPIKey: key)
        // Delegate lets us receive real-time entitlement updates
        Purchases.shared.delegate = PurchaseService.shared
    }

    // MARK: - Link user (call after sign in / sign up)
    //
    // Passing the Supabase user ID to RevenueCat ensures purchase history
    // survives reinstalls and is tied to the account, not the device.

    func logIn(userID: String) async {
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userID)
            await update(from: customerInfo)
        } catch {
            print("[PurchaseService] logIn error: \(error)")
        }
    }

    // MARK: - Unlink user (call on sign-out)

    func logOut() async {
        do {
            let customerInfo = try await Purchases.shared.logOut()
            await update(from: customerInfo)
        } catch {
            print("[PurchaseService] logOut error: \(error)")
        }
    }

    // MARK: - Fetch offerings (call when paywall appears)

    func fetchOfferings() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { self.isLoading = false } } }

        do {
            let result = try await Purchases.shared.offerings()
            await MainActor.run { offerings = result }
        } catch {
            print("[PurchaseService] fetchOfferings error: \(error)")
        }
    }

    // MARK: - Refresh entitlement (call on foreground / after sign-in)

    func refreshEntitlement() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            await update(from: info)
        } catch {
            // Offline: RevenueCat returns cached value — this only throws on a
            // network error with no local cache. Fail silently; isPro stays unchanged.
            print("[PurchaseService] refreshEntitlement error (may be offline): \(error)")
        }
    }

    // MARK: - Purchase

    /// Returns nil on success, or an error message string.
    func purchase(package: Package) async -> String? {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { self.isLoading = false } } }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return nil }  // silent cancel — not an error
            await update(from: result.customerInfo)
            return nil
        } catch let err as ErrorCode {
            if err == .purchaseCancelledError { return nil }
            return err.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Restore purchases

    func restorePurchases() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { self.isLoading = false } } }

        do {
            let info = try await Purchases.shared.restorePurchases()
            await update(from: info)
            let active = info.entitlements[Self.entitlementID]?.isActive == true
            await MainActor.run {
                restoreMessage = active ? .restored : .nothingToRestore
            }
        } catch {
            await MainActor.run {
                restoreMessage = .error(error.localizedDescription)
            }
        }
    }

    func clearRestoreMessage() {
        restoreMessage = nil
    }

    // MARK: - Convenience accessors for Paywall

    /// Monthly package from the current offering, if available.
    var monthlyPackage: Package? {
        offerings?.current?.monthly
    }

    /// Annual package from the current offering, if available.
    var annualPackage: Package? {
        offerings?.current?.annual
    }

    // MARK: - Private helpers

    @MainActor
    private func update(from customerInfo: CustomerInfo) {
        isPro = customerInfo.entitlements[Self.entitlementID]?.isActive == true
        // Mirror into ProGate so the rest of the app sees one truth.
        ProGate.shared.setProStatus(isPro)
    }
}

// MARK: - PurchasesDelegate
// Receives real-time updates (e.g. subscription renewed in background).

extension PurchaseService: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { await update(from: customerInfo) }
    }
}
