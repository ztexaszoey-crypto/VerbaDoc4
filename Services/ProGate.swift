import SwiftUI
import SwiftData
import Combine

// MARK: - ProGate
//
// Single source of truth for free-tier limits and Pro status.
// isPro is driven exclusively by PurchaseService (RevenueCat entitlement "pro").
// Never set isPro directly — call PurchaseService and it will call setProStatus().
//
// Free tier:
//   • 5 decks max
//   • 10 AI generations total (lifetime)
//   • 25 cards per deck max
//   • No exam mode
//   • No export/share

final class ProGate: ObservableObject {

    static let shared = ProGate()

    // MARK: - Pro status (driven by PurchaseService → RevenueCat)

    @Published private(set) var isPro: Bool = false

    /// Called exclusively by PurchaseService after receiving CustomerInfo from RevenueCat.
    func setProStatus(_ value: Bool) {
        DispatchQueue.main.async {
            self.isPro = value
        }
    }

    // MARK: - Limits

    enum Limit {
        static let maxDecks        = 10
        static let maxCardsPerDeck = 50
        static let maxAIGenerations = 30
    }

    // AI generation counter lives in Keychain (survives reinstall on same device +
    // same Apple ID), which prevents the trivial `uninstall → reinstall → 30 more
    // free generations` exploit cycle. Per-device so a new test account cannot
    // bypass by signing in with another email.
    //
    // The value is cached in a Published property so UploadTabView can read it
    // every render without repeatedly hitting the Security framework.
    private var aiGenKey: KeychainService.Key { .freeAIGenerations }

    @Published private var cachedAIGenerationsUsed: Int

    private init() {
        // Synchronous read at first-touch; this is once per app launch.
        if let str = KeychainService.get(.freeAIGenerations), let val = Int(str) {
            self.cachedAIGenerationsUsed = val
        } else {
            self.cachedAIGenerationsUsed = 0
        }
    }

    var aiGenerationsUsed: Int {
        get { cachedAIGenerationsUsed }
        set {
            cachedAIGenerationsUsed = newValue
            KeychainService.set(String(newValue), for: aiGenKey)
        }
    }

    var aiGenerationsRemaining: Int {
        max(0, Limit.maxAIGenerations - aiGenerationsUsed)
    }

    func recordAIGeneration() {
        guard !isPro else { return }
        aiGenerationsUsed += 1
    }

    // MARK: - Gate checks (return true = allowed)

    func canCreateDeck(existingCount: Int) -> Bool {
        isPro || existingCount < Limit.maxDecks
    }

    func canGenerateAI() -> Bool {
        isPro || aiGenerationsUsed < Limit.maxAIGenerations
    }

    func canAddCard(currentCount: Int) -> Bool {
        isPro || currentCount < Limit.maxCardsPerDeck
    }

    func canUseExamMode() -> Bool {
        isPro
    }

    func canExport() -> Bool {
        isPro
    }

    // MARK: - Paywall trigger reason

    enum GateReason {
        case deckLimit, aiLimit, cardLimit, examMode, export

        var headline: String {
            switch self {
            case .deckLimit:  return "you've hit the free deck limit"
            case .aiLimit:    return "you've used your free AI generations"
            case .cardLimit:  return "deck card limit reached"
            case .examMode:   return "exam mode is pro"
            case .export:     return "sharing is a pro feature"
            }
        }

        var subtitle: String {
            switch self {
            case .deckLimit:  return "Free plan includes \(Limit.maxDecks) decks. Go Pro for unlimited."
            case .aiLimit:    return "You've used your \(Limit.maxAIGenerations) free AI generations. Go Pro for unlimited."
            case .cardLimit:  return "Free plan caps decks at \(Limit.maxCardsPerDeck) cards. Go Pro for unlimited."
            case .examMode:   return "Multiple choice exam mode is a Pro feature."
            case .export:     return "Export to Anki, CSV, and more with Pro. Free users can still share as text."
            }
        }
    }
}

// MARK: - GatedModifier
// Wraps any view with a paywall trigger.
// Usage: someView.gated(by: .examMode)

struct GatedModifier: ViewModifier {
    let reason: ProGate.GateReason
    @ObservedObject private var gate = ProGate.shared
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(true)
            .onTapGesture {
                if shouldBlock {
                    HapticManager.impact(.light)
                    showPaywall = true
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }

    private var shouldBlock: Bool {
        switch reason {
        case .examMode: return !gate.canUseExamMode()
        case .export:   return !gate.canExport()
        default:        return false
        }
    }
}

extension View {
    func gated(by reason: ProGate.GateReason) -> some View {
        modifier(GatedModifier(reason: reason))
    }
}
