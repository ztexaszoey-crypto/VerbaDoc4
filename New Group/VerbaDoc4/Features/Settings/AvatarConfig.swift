import SwiftUI

// MARK: - AvatarConfig
//
// Fully codable avatar configuration stored as JSON in AppStorage.
// Key: "profile.avatarConfig"
//
// Dimensions are expressed as ratios of the avatar's bounding size
// so the capybara renders correctly at any size (36pt thumbnail → 120pt profile).

struct AvatarConfig: Codable, Equatable {
    var furColor  : FurColor  = .brown
    var eyeStyle  : EyeStyle  = .normal
    var blush     : Bool      = true
    var accessory : Accessory = .none
    var bgColor   : BgColor   = .sage

    // MARK: - Fur Color

    enum FurColor: String, Codable, CaseIterable {
        case brown, caramel, gray, cream, rosePink, midnight, olive, sky

        var color: Color {
            switch self {
            case .brown:    return Color(red: 0.56, green: 0.39, blue: 0.23)
            case .caramel:  return Color(red: 0.78, green: 0.57, blue: 0.30)
            case .gray:     return Color(red: 0.60, green: 0.60, blue: 0.62)
            case .cream:    return Color(red: 0.90, green: 0.83, blue: 0.70)
            case .rosePink: return Color(red: 0.88, green: 0.58, blue: 0.68)
            case .midnight: return Color(red: 0.18, green: 0.16, blue: 0.22)
            case .olive:    return Color(red: 0.48, green: 0.52, blue: 0.26)
            case .sky:      return Color(red: 0.42, green: 0.68, blue: 0.88)
            }
        }

        /// Snout / ear inner — slightly lighter/warmer than fur
        var snoutColor: Color { color.opacity(0.7) }

        var name: String {
            switch self {
            case .brown:    return "brown"
            case .caramel:  return "caramel"
            case .gray:     return "gray"
            case .cream:    return "cream"
            case .rosePink: return "rose"
            case .midnight: return "midnight"
            case .olive:    return "olive"
            case .sky:      return "sky"
            }
        }
    }

    // MARK: - Eye Style

    enum EyeStyle: String, Codable, CaseIterable {
        case normal, happy, sleepy, starry, cool

        var name: String {
            switch self {
            case .normal: return "chill"
            case .happy:  return "happy"
            case .sleepy: return "sleepy"
            case .starry: return "starry"
            case .cool:   return "cool"
            }
        }

        var icon: String {
            switch self {
            case .normal: return "•  •"
            case .happy:  return "^  ^"
            case .sleepy: return "—  —"
            case .starry: return "★  ★"
            case .cool:   return "▬  ▬"
            }
        }
    }

    // MARK: - Accessory

    enum Accessory: String, Codable, CaseIterable {
        case none, graduationCap, flowerCrown, beanie, partyHat,
             bow, sunglasses, crown, cowboyHat, halo

        var emoji: String {
            switch self {
            case .none:          return ""
            case .graduationCap: return "🎓"
            case .flowerCrown:   return "🌸"
            case .beanie:        return "🧢"
            case .partyHat:      return "🎉"
            case .bow:           return "🎀"
            case .sunglasses:    return "🕶️"
            case .crown:         return "👑"
            case .cowboyHat:     return "🤠"
            case .halo:          return "😇"
            }
        }

        var name: String {
            switch self {
            case .none:          return "none"
            case .graduationCap: return "grad cap"
            case .flowerCrown:   return "flowers"
            case .beanie:        return "beanie"
            case .partyHat:      return "party"
            case .bow:           return "bow"
            case .sunglasses:    return "shades"
            case .crown:         return "crown"
            case .cowboyHat:     return "cowboy"
            case .halo:          return "halo"
            }
        }
    }

    // MARK: - Background Color

    enum BgColor: String, Codable, CaseIterable {
        case sage, sky, peach, lavender, gold, mint, coral, slate, cream, rose

        var color: Color {
            switch self {
            case .sage:     return Color(red: 0.62, green: 0.76, blue: 0.64)
            case .sky:      return Color(red: 0.55, green: 0.76, blue: 0.92)
            case .peach:    return Color(red: 0.98, green: 0.78, blue: 0.64)
            case .lavender: return Color(red: 0.76, green: 0.66, blue: 0.90)
            case .gold:     return Color(red: 0.98, green: 0.84, blue: 0.40)
            case .mint:     return Color(red: 0.62, green: 0.90, blue: 0.80)
            case .coral:    return Color(red: 0.96, green: 0.60, blue: 0.58)
            case .slate:    return Color(red: 0.60, green: 0.66, blue: 0.76)
            case .cream:    return Color(red: 0.96, green: 0.92, blue: 0.82)
            case .rose:     return Color(red: 0.94, green: 0.74, blue: 0.80)
            }
        }

        var name: String { rawValue }
    }
}

// MARK: - AppStorage helpers

extension AvatarConfig {
    /// Reads AvatarConfig from AppStorage JSON string. Returns default on decode failure.
    static func load(from json: String) -> AvatarConfig {
        guard
            let data   = json.data(using: .utf8),
            let config = try? JSONDecoder().decode(AvatarConfig.self, from: data)
        else { return AvatarConfig() }
        return config
    }

    /// Encodes to JSON string for AppStorage.
    func encoded() -> String {
        guard
            let data = try? JSONEncoder().encode(self),
            let str  = String(data: data, encoding: .utf8)
        else { return "" }
        return str
    }
}
