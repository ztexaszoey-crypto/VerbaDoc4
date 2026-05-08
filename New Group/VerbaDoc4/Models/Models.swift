import Foundation
import SwiftUI

// MARK: - Subject

struct Subject: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color

    static let all: [Subject] = [
        Subject(name: "Mathematics",  icon: "function",           color: Color(red: 0.25, green: 0.55, blue: 0.95)),
        Subject(name: "Science",      icon: "atom",               color: Color(red: 0.35, green: 0.76, blue: 0.57)),
        Subject(name: "History",      icon: "building.columns",   color: Color(red: 0.93, green: 0.65, blue: 0.25)),
        Subject(name: "Language",     icon: "textformat",         color: Color(red: 0.72, green: 0.45, blue: 0.90)),
        Subject(name: "Arts",         icon: "paintbrush",         color: Color(red: 0.95, green: 0.45, blue: 0.60)),
        Subject(name: "Technology",   icon: "cpu",                color: Color(red: 0.20, green: 0.70, blue: 0.85)),
        Subject(name: "Geography",    icon: "globe",              color: Color(red: 0.50, green: 0.80, blue: 0.40)),
        Subject(name: "Philosophy",   icon: "brain.head.profile", color: Color(red: 0.60, green: 0.40, blue: 0.75)),
        Subject(name: "Economics",    icon: "chart.bar.fill",     color: Color(red: 1.00, green: 0.78, blue: 0.15)),
        Subject(name: "Literature",   icon: "book.fill",          color: Color(red: 0.80, green: 0.35, blue: 0.30)),
    ]
}

// MARK: - UserProfile

struct UserProfile {
    var name: String
    var grade: String
    var age: Int
    var email: String
    var avatarSymbol: String
    var studyGoal: Int
    var preferredSubjects: [Subject]

    init(
        name: String = "",
        grade: String = "",
        age: Int = 0,
        email: String = "",
        avatarSymbol: String = "books.vertical.fill",
        studyGoal: Int = 20,
        preferredSubjects: [Subject] = []
    ) {
        self.name = name
        self.grade = grade
        self.age = age
        self.email = email
        self.avatarSymbol = avatarSymbol
        self.studyGoal = studyGoal
        self.preferredSubjects = preferredSubjects
    }
}

struct AvatarOption: Identifiable, Hashable {
    let symbol: String
    let name: String
    let category: String

    var id: String { "\(category)-\(symbol)" }

    static let all: [AvatarOption] = [
        AvatarOption(symbol: "books.vertical.fill", name: "Bookworm", category: "Study"),
        AvatarOption(symbol: "graduationcap.fill", name: "Scholar", category: "Study"),
        AvatarOption(symbol: "brain.head.profile", name: "Thinker", category: "Study"),
        AvatarOption(symbol: "lightbulb.fill", name: "Idea", category: "Study"),
        AvatarOption(symbol: "leaf.fill", name: "Leaf", category: "Nature"),
        AvatarOption(symbol: "sun.max.fill", name: "Sunny", category: "Nature"),
        AvatarOption(symbol: "moon.stars.fill", name: "Moon", category: "Nature"),
        AvatarOption(symbol: "ant.fill", name: "Busy Bee", category: "Animals"),
        AvatarOption(symbol: "tortoise.fill", name: "Steady", category: "Animals"),
        AvatarOption(symbol: "hare.fill", name: "Quick", category: "Animals"),
        AvatarOption(symbol: "theatermasks.fill", name: "Creative", category: "Creative"),
        AvatarOption(symbol: "paintpalette.fill", name: "Palette", category: "Creative")
    ]
}

// MARK: - StudySession

struct StudySession: Identifiable {
    let id = UUID()
    let date: Date
    let cardsReviewed: Int
    let correctCount: Int
    let duration: TimeInterval

    var accuracy: Double {
        cardsReviewed > 0 ? Double(correctCount) / Double(cardsReviewed) : 0
    }

    var accuracyPercentage: String {
        "\(Int(accuracy * 100))%"
    }
}

// MARK: - TutorMessage

struct TutorMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case tutor
        case student
    }

    init(role: Role, content: String) {
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

struct CommunityStudent: Identifiable, Hashable {
    let id: String
    let name: String
    let grade: String
    let avatarSymbol: String
    let bio: String
    let isOnline: Bool

    static let featured: [CommunityStudent] = [
        CommunityStudent(id: "maya", name: "Maya", grade: "Grade 10", avatarSymbol: "moon.stars.fill", bio: "Biology + history notes queen.", isOnline: true),
        CommunityStudent(id: "leo", name: "Leo", grade: "Grade 11", avatarSymbol: "brain.head.profile", bio: "Math proofs and exam hacks.", isOnline: true),
        CommunityStudent(id: "sana", name: "Sana", grade: "Grade 9", avatarSymbol: "paintpalette.fill", bio: "Makes flashcards for everything.", isOnline: false)
    ]
}

struct CommunityChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let sender: String
    let body: String
    let timestamp: Date
    let isCurrentUser: Bool

    init(id: UUID = UUID(), sender: String, body: String, timestamp: Date = Date(), isCurrentUser: Bool) {
        self.id = id
        self.sender = sender
        self.body = body
        self.timestamp = timestamp
        self.isCurrentUser = isCurrentUser
    }
}

struct StudyChallenge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let xpReward: Int
    let isCompleted: Bool
    let isClaimed: Bool
}
