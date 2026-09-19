import Foundation
import SwiftUI

// MARK: - Phase 21: Four Worlds palette
//
// Subway Surfers has themed worlds (NYC, Paris, Tokyo, etc.).
// VerbaDoc can't ship high-fidelity 3D worlds without proper art,
// but a palette swap + sky-color shift is the cheapest way to give
// the runner a strong sense of progression. Each world is a
// (skyTop, skyBottom, ground, accent, fog) tuple. CapySurfersScene
// reads `currentWorld` at world-switch time and applies the palette
// to its gradient layers + parallax bands.
//
// Unlock rules (Phase 21 — pure totalMelons, no StreakManager
// dependency, no `weak stored property in extension` trap):
//   campus  -- default from launch
//   library -- at 25 lifetime watermelons
//   science -- at 100 lifetime watermelons
//   space   -- at 250 lifetime watermelons

enum CapyWorld: String, CaseIterable, Identifiable, Codable {
    case campus  = "campus"
    case library = "library"
    case science = "science"
    case space   = "space"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .campus:  return "Campus Run"
        case .library: return "Library Escape"
        case .science: return "Science Lab"
        case .space:   return "Space Zone"
        }
    }

    var unlockHint: String {
        switch self {
        case .campus:  return "Default"
        case .library: return "Earn 25 watermelons"
        case .science: return "Earn 100 watermelons"
        case .space:   return "Earn 250 watermelons"
        }
    }

    /// Hex tuples -- (skyTop, skyBottom, ground, accent, fog). All
    /// pastel family so the cozy-green identity survives the swap;
    /// we vary hue, not saturation.
    var palette: (skyTop: UInt32, skyBottom: UInt32, ground: UInt32, accent: UInt32, fog: UInt32) {
        switch self {
        case .campus:
            return (0xC8E8A2, 0xF7E5A2, 0xC4DF88, 0x9CD443, 0x9DC4E2)
        case .library:
            return (0xC8C6E8, 0xE0DEF1, 0xC9A988, 0x8B6F47, 0xB0AECF)
        case .science:
            return (0xBCE6D6, 0xD7F3E4, 0xA8D6C8, 0x2EB39A, 0x82D2BB)
        case .space:
            return (0x1A1F2E, 0x3F4A6C, 0x2A2F45, 0xFFB347, 0x2B2F45)
        }
    }
}

// MARK: - Phase 21: Daily Mission types

enum CapyMissionType: String, CaseIterable, Codable {
    case collectMelons  // collect 30 melons in one run
    case travelMeters   // travel 1,500 m in one run
    case answerCorrect  // answer 3 refuels correctly in one run
    case runLongEnough  // complete one run > 30 s without bailing

    var target: Int {
        switch self {
        case .collectMelons:  return 30
        case .travelMeters:   return 1500
        case .answerCorrect:  return 3
        case .runLongEnough:  return 30
        }
    }

    var label: String {
        switch self {
        case .collectMelons:  return "Collect 30 melons in one run"
        case .travelMeters:   return "Travel 1,500 m in one run"
        case .answerCorrect:  return "Answer 3 refuels correctly"
        case .runLongEnough:  return "Survive 30 seconds in a run"
        }
    }

    var rewardMelons: Int { 30 }
    var rewardXP: Int { 75 }
}

struct CapyMission: Equatable {
    let type: CapyMissionType
    let date: Date
    var progress: Int
    var claimed: Bool

    init(type: CapyMissionType, date: Date, progress: Int = 0, claimed: Bool = false) {
        self.type = type
        self.date = date
        self.progress = progress
        self.claimed = claimed
    }
}

// MARK: - Phase 21: Local-day key helper
//
// Helper is shared between CapySurfersState extension and any
// future mission-aware UI. YYYY-MM-DD keys are stable across DST
// and are < the floating-point risk of comparing Date() values for
// "is it still today's mission".

enum CapyDayKey {
    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}

// MARK: - Phase 21: Mission helpers exposed as free functions
//
// These operate on CapySurfersState's @AppStorage properties without
// requiring changes to the State class itself -- the state class
// already has the four mission @AppStorage keys plus the multiplier
// runtime state from Patch 2. The free functions read / write those
// published properties via the singleton instance.
//
// Note on call-site naming: `target` / `label` / `rewardMelons` /
// `rewardXP` all live on `CapyMissionType`, NOT on `CapyMission`.
// The mission record holds the *current* progress / claim state;
// the goal metadata stays on the type. Read with `m.type.target`,
// matching the grace-window check above (`prevType.target`).

enum CapyMissionEngine {

    /// Look up today's mission. Stable across launches that share a
    /// calendar day. Includes a 6-hour grace window so a near-complete
    /// mission isn't vaporized at midnight rollover.
    ///
    /// Logic:
    ///   1) Same-day fast path       -- return current progress
    ///   2) Grace window check       -- if previous day hit target but
    ///                                   unclaimed <= 6 h post-rollover,
    ///                                   freeze entry for claim
    ///   3) Fresh-mission picker     -- deterministic by day-of-month
    static func rollIfNeeded(state: CapySurfersState, now: Date = Date()) -> CapyMission {
        let day = CapyDayKey.key(for: now)
        if state.dailyMissionDate == day,
           let raw = CapyMissionType(rawValue: state.dailyMissionID) {
            return CapyMission(
                type: raw, date: now,
                progress: state.dailyMissionProgress,
                claimed: !state.dailyMissionClaimedAt.isEmpty
            )
        }
        if !state.dailyMissionID.isEmpty,
           let prevType = CapyMissionType(rawValue: state.dailyMissionID),
           state.dailyMissionProgress >= prevType.target,
           state.dailyMissionClaimedAt.isEmpty,
           let lastRollDate = CapyDayKey.date(from: state.dailyMissionDate),
           now.timeIntervalSince(lastRollDate) <= 6 * 3600 {
            return CapyMission(
                type: prevType, date: now,
                progress: state.dailyMissionProgress, claimed: false
            )
        }
        let all = CapyMissionType.allCases
        let dayOfMonth = Calendar.current.component(.day, from: now)
        let next = all[(max(dayOfMonth, 1) - 1) % all.count]
        state.dailyMissionID = next.rawValue
        state.dailyMissionDate = day
        state.dailyMissionProgress = 0
        state.dailyMissionClaimedAt = ""
        return CapyMission(type: next, date: now, progress: 0, claimed: false)
    }

    /// Increment progress clamped to target.
    static func recordProgress(_ delta: Int, state: CapySurfersState) {
        let m = rollIfNeeded(state: state)
        state.dailyMissionProgress = max(0, min(state.dailyMissionProgress + delta, m.type.target))
    }

    /// True iff the current mission is at target and unclaimed.
    static var claimable: Bool {
        let m = rollIfNeeded(state: CapySurfersState.shared)
        return !m.claimed && m.progress >= m.type.target
    }

    /// Claim today's reward: +30 melons + claim timestamp. Locked by
    /// `claimable` so the reward cannot be claimed twice within the
    /// same calendar day.
    static func claimReward(state: CapySurfersState = .shared) {
        guard claimable else { return }
        state.totalMelons += 30
        state.dailyMissionClaimedAt = CapyDayKey.key(for: Date())
    }
}

// MARK: - Phase 21: World helpers as free functions
//
// Pure totalMelons check -- no StreakManager dependency and no
// `weak stored property in extension` (which would fail to compile).

enum CapyWorldGate {
    static func unlocked(_ w: CapyWorld, melons: Int) -> Bool {
        switch w {
        case .campus:  return true
        case .library: return melons >= 25
        case .science: return melons >= 100
        case .space:   return melons >= 250
        }
    }

    static func highestUnlocked(melons: Int) -> CapyWorld {
        if melons >= 250 { return .space }
        if melons >= 100 { return .science }
        if melons >= 25  { return .library }
        return .campus
    }
}

// MARK: - Phase 21: Color helpers for palette hex -> Color

extension UInt32 {
    /// Returns a SwiftUI Color from a 0xRRGGBB hex value (alpha 1).
    /// Centralised so every palette read uses the same conversion.
    var swiftUIColor: Color {
        let r = Double((self >> 16) & 0xFF) / 255.0
        let g = Double((self >> 8)  & 0xFF) / 255.0
        let b = Double(self & 0xFF)        / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
