import Foundation

// MARK: - EngineSnapshot
//
// Immutable snapshot of VerbaFlowEngine state used to drive game parameters.
// Captures only the fields the game logic needs — no engine reference held here.

struct EngineSnapshot {
    let energy: Double
    let mode:   VerbaFlowEngine.FlowMode

    static let `default` = EngineSnapshot(energy: 50, mode: .normal)
}

// MARK: - GameBridge
//
// Stateless translator between VerbaFlowEngine state and SpriteKit game parameters.
// All methods are pure functions — no stored state, no side-effects.
//
// Tuning intent:
//   Flow mode    → faster, tighter spawns (reward for mastery)
//   Normal mode  → baseline experience
//   Review mode  → slightly slower, more breathing room
//   Recovery mode → noticeably easier (student is struggling)

enum GameBridge {

    // MARK: - Speed

    /// Multiplier applied on top of the base distance-ramp speed.
    /// 1.0 = baseline. Values outside 0.65–1.35 feel too punishing/easy.
    static func speedMultiplier(for snapshot: EngineSnapshot) -> Double {
        switch snapshot.mode {
        case .flow:     return 1.30
        case .normal:   return 1.00
        case .review:   return 0.85
        case .recovery: return 0.65
        }
    }

    // MARK: - Spawn Interval

    /// Scale factor applied to obstacle spawn interval.
    /// >1.0 = more time between obstacles (easier). <1.0 = tighter (harder).
    static func spawnIntervalScale(for snapshot: EngineSnapshot) -> Double {
        switch snapshot.mode {
        case .flow:     return 0.75   // more frequent — flow state earns challenge
        case .normal:   return 1.00
        case .review:   return 1.25   // more breathing room
        case .recovery: return 1.55   // generous spacing
        }
    }

    // MARK: - Gate Distance Interval

    /// Metres between gate checkpoints. Lower energy → more frequent gates.
    static func gateDistanceInterval(for snapshot: EngineSnapshot) -> Int {
        switch snapshot.mode {
        case .flow:     return 500
        case .normal:   return 300
        case .review:   return 200
        case .recovery: return 100
        }
    }
}
