import Foundation

struct VerbaCharacter: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let message: String

    static let onboardingSteps: [VerbaCharacter] = [
        VerbaCharacter(name: "Welcome", symbol: "sparkles", message: "Turn notes into study cards in seconds."),
        VerbaCharacter(name: "Practice", symbol: "rectangle.stack.badge.play", message: "Review due cards daily to retain more."),
        VerbaCharacter(name: "Track", symbol: "chart.line.uptrend.xyaxis", message: "Build your streak with short sessions.")
    ]
}
