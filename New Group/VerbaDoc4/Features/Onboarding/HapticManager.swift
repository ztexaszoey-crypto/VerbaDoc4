import UIKit

enum HapticManager {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
