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
    var age: Int
    var studyGoal: Int
    var preferredSubjects: [Subject]

    init(name: String = "", age: Int = 0, studyGoal: Int = 20, preferredSubjects: [Subject] = []) {
        self.name = name
        self.age = age
        self.studyGoal = studyGoal
        self.preferredSubjects = preferredSubjects
    }
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
