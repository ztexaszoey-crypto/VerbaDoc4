import Foundation
import AVFoundation

// MARK: - CapyAudio
//
// Phase 22 polish: thin AVAudioPlayer wrapper. Filenames dictate the
// asset contract: `sfx_<name>.mp3` in the bundle. No files bundled
// today; play(_:) silently no-ops in dev if missing.

enum CapySound: String, Sendable, CaseIterable {
    case coin    = "sfx_coin"
    case jump    = "sfx_jump"
    case slide   = "sfx_slide"
    case powerup = "sfx_powerup"
    case crash   = "sfx_crash"
    case victory = "sfx_victory"
    case streak  = "sfx_streak"

    var fileExtension:  String { "mp3" }
    var bundleResource: String { "\(rawValue).\(fileExtension)" }

    var displayName: String {
        switch self {
        case .coin:    return "Coin collected"
        case .jump:    return "Jump"
        case .slide:   return "Slide"
        case .powerup: return "Power-up collected"
        case .crash:   return "Hit an obstacle"
        case .victory: return "Run complete"
        case .streak:  return "Streak milestone"
        }
    }
}

@MainActor
final class CapyAudioEngine {

    static let shared = CapyAudioEngine()

    private var cache: [CapySound: AVAudioPlayer] = [:]

    var muted: Bool = false
    var volume: Float = 0.85

    private init() {}

    private func ensurePlayer(for sound: CapySound) -> AVAudioPlayer? {
        if let cached = cache[sound] { return cached }
        guard let url = Bundle.main.url(
            forResource: sound.rawValue,
            withExtension: sound.fileExtension
        ) else {
            #if DEBUG
            print("[CapyAudio] asset not bundled; silent no-op for \(sound.bundleResource)")
            #endif
            return nil
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            cache[sound] = p
            return p
        } catch {
            #if DEBUG
            print("[CapyAudio] failed to load \(sound.bundleResource): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func play(_ sound: CapySound) {
        guard !muted else { return }
        guard let player = ensurePlayer(for: sound) else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    func preload() {
        CapySound.allCases.forEach { _ = ensurePlayer(for: $0) }
    }
}
