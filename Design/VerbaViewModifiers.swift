import SwiftUI

// MARK: - Verba view modifiers
//
// Two custom modifiers used in CapyRunnerLaunchView.swift that were
// never actually defined anywhere in the project — verified by
// grepping every .verba*( call across the whole codebase, this is
// the complete set, nothing else missing of this kind.

extension View {
    /// A soft elevated-card shadow — the "lift" amount controls how
    /// far off the page the element looks like it's floating. Matches
    /// ClayGlassSystem's contact-shadow language (hard-ish offset, not
    /// a big soft blur) rather than a generic drop shadow.
    func verbaElevation(_ lift: CGFloat) -> some View {
        self.shadow(color: VerbaTheme.shadow(0.22), radius: lift * 0.6, x: 0, y: lift * 0.5)
    }

    /// Small pill-shaped tab chip — active state uses the forest-green
    /// accent with a filled background; inactive is a plain outline.
    /// Used for things like a small in-context tab switcher.
    func verbaTabChip(isActive: Bool) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? VerbaTheme.cozyForest.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? VerbaTheme.cozyForest : VerbaTheme.oliveBorder, lineWidth: 1.5)
            )
    }
}
