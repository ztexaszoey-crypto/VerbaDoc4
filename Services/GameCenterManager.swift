import Foundation
import GameKit

final class GameCenterManager {
    static let shared = GameCenterManager()
    private init() {}

    func authenticate() {
        let player = GKLocalPlayer.local
        player.authenticateHandler = { viewController, error in
            if let error = error {
                #if DEBUG
                print("[GameCenter] Auth failed: \(error.localizedDescription)")
                #endif
                return
            }
            if viewController != nil {
                // Presentation handled by the system on first launch
                return
            }
            #if DEBUG
            if player.isAuthenticated {
                print("[GameCenter] Authenticated as \(player.displayName)")
            }
            #endif
        }
    }
}
