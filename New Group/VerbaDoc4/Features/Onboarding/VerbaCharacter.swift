import Foundation

struct VerbaCharacter: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let message: String

    static let onboardingSteps: [VerbaCharacter] = [
        VerbaCharacter(name: "Meet Verba", symbol: "sparkles", message: "Upload notes, PDFs, and homework photos to build flashcards fast."),
        VerbaCharacter(name: "Study Smarter", symbol: "rectangle.stack.badge.play", message: "Use due reviews, weak-card practice, and swipe sessions to remember more."),
        VerbaCharacter(name: "Stay Ready", symbol: "chart.line.uptrend.xyaxis", message: "Track mastery, countdown to exams, and keep your streak alive."),
        VerbaCharacter(name: "Make It Yours", symbol: "person.crop.circle.badge.checkmark", message: "Pick your avatar, reminders, and study profile before you jump in.")
    ]
}
