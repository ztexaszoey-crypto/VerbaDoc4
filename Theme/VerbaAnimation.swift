import SwiftUI

extension Animation {
    static let verba = Animation.spring(response: 0.35, dampingFraction: 0.75)

    // MARK: - Pastel motion primitives (Phase 1)
    //
    // Each named spring has a documented emotional intent. Reach for them
    // by name so screens across the app feel physically consistent.

    /// Cards / surfaces that lift gently on hover or activation. Slight
    /// wobble so the motion reads as physical, not robotic.
    static let lift = Animation.spring(response: 0.40, dampingFraction: 0.65)

    /// Soft-button compression — used by ScaleButtonStyle & older in-flight
    /// pastel paths. Slower, smoother than `.bounceIn`.
    static let squish = Animation.spring(response: 0.20, dampingFraction: 0.70)

    /// Reward / success scale-up (XP pulse, coin collection, mastery gain).
    /// Higher bounce so the reward reads as celebratory.
    static let sparkle = Animation.spring(response: 0.35, dampingFraction: 0.45)

    /// Modal / sheet / card-on-card entrance. Heavier than `.lift`.
    static let pop = Animation.spring(response: 0.45, dampingFraction: 0.75)

    /// Slow drifting motion for backdrop blobs.
    static let float = Animation.spring(response: 3.0, dampingFraction: 1.0, blendDuration: 1.0)

    // MARK: - FELIwS motion primitive (Phase 2)
    //
    // Chunky plastic button press: faster in, slightly springier out than
    // `.squish`. Use on `.isPressed` for the chunky mint CTAs so they feel
    // like real plastic snapping into the screen.
    static let bounceIn = Animation.spring(response: 0.16, dampingFraction: 0.62)
}
