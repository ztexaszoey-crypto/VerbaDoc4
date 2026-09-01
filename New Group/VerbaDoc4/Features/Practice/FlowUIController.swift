import SwiftUI

/// Pure render state derived from VerbaFlowEngine.
///
/// Contains ONLY display values — no learning logic, no data mutations.
/// All learning decisions live in FlowEngine, GateScheduler, MasteryTracker.
/// The View creates this from engine state and reads it for every rendering decision.
struct FlowUIController {

    let energy: Double
    let mode: VerbaFlowEngine.FlowMode
    let isGate: Bool
    let streakCount: Int
    let flowSpeedMultiplier: Double

    // MARK: - Color

    var modeColor: Color {
        switch mode {
        case .flow:     return VerbaTheme.green
        case .normal:   return VerbaTheme.yellow
        case .review:   return VerbaTheme.orange
        case .recovery: return VerbaTheme.danger
        }
    }

    // MARK: - Labels

    var modeLabel: String { mode.rawValue }

    var modeSubtitle: String {
        switch mode {
        case .flow:     return "locked in — keep the momentum"
        case .normal:   return "steady pace"
        case .review:   return "slow down — reveal before marking correct"
        case .recovery: return "recovery — weak concepts reinforced"
        }
    }

    // MARK: - Motion (UI-only — not gameplay)

    /// Card transition duration in seconds.
    /// Derives from flowSpeedMultiplier: higher energy → crisper transitions.
    /// This is purely cosmetic pacing feedback — it does not affect learning.
    var cardTransitionDuration: Double {
        max(0.10, 0.20 / flowSpeedMultiplier)
        // flow (1.5×) → ~0.13s  |  normal (0.75×) → ~0.27s  |  recovery (0.5×) → 0.40s
    }

    // MARK: - Energy Bar

    /// Fraction 0–1 for rendering the energy progress bar.
    var energyFill: Double { energy / 100.0 }

    // MARK: - Gate

    var showGateIndicator: Bool { isGate }

    // MARK: - Streak

    /// Badge text — only rendered at 3+ consecutive correct.
    var streakBadgeText: String? {
        streakCount >= 3 ? "\(streakCount)×" : nil
    }
}
