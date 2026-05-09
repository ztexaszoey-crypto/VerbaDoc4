import SwiftUI

// PaywallView now forwards to UnlocksView.
// Kept for compatibility with any remaining call sites.
struct PaywallView: View {
    var body: some View {
        UnlocksView()
    }
}
