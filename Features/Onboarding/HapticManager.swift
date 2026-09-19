import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum HapticManager {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Phase 5 (Refuel & Surf): fires when Capy's juice hits 0 mid-run
    /// so the player feels the freeze as a notification-style alert
    /// rather than a generic tap impact. Pairs with `success()` —
    /// both delegate to `UINotificationFeedbackGenerator`.
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    static func light() {
        impact(.light)
    }

    static func medium() {
        impact(.medium)
    }

    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
