import SwiftUI
import Combine

// MARK: - Game state (ObservableObject bridges SpriteKit ↔ SwiftUI)

final class VerbaFlowState: ObservableObject {

    @Published var score:           Int = 0
    @Published var lives:           Int = 3
    @Published var barriers:        Int = 0
    @Published var correctAnswers:  Int = 0
    @Published var showQuestion:    Bool = false
    @Published var currentQuestion: FlowQuestion? = nil
    @Published var isGameOver:      Bool = false
    @Published var freeResponseText: String = ""

    // Called by scene when barrier is hit
    func presentQuestion(_ q: FlowQuestion) {
        currentQuestion = q
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showQuestion = true
        }
        barriers += 1
    }

    // Called by SwiftUI when user picks answer
    func answerQuestion(correct: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showQuestion = false
        }
        currentQuestion = nil

        if correct {
            correctAnswers += 1
            score += 50
        } else {
            loseLife()
        }

        // Tell the scene to resume
        NotificationCenter.default.post(
            name: .verbaFlowAnswered,
            object: nil,
            userInfo: ["correct": correct]
        )
    }

    func addScore(_ n: Int) { score += n }

    func loseLife() {
        lives -= 1
        if lives <= 0 { triggerGameOver() }
    }

    func triggerGameOver() {
        withAnimation { isGameOver = true }
    }

    func restart() {
        score = 0
        lives = 3
        barriers = 0
        correctAnswers = 0
        showQuestion = false
        currentQuestion = nil
        isGameOver = false
        freeResponseText = ""
        NotificationCenter.default.post(name: .verbaFlowRestart, object: nil)
    }
}

// MARK: - Question model

struct FlowQuestion {
    let question:     String
    let options:      [String]
    let correctIndex: Int
    let topic:        String
    let isMCQ:        Bool
}

// MARK: - Notification names

extension Notification.Name {
    static let verbaFlowAnswered = Notification.Name("verbaFlowAnswered")
    static let verbaFlowRestart  = Notification.Name("verbaFlowRestart")
}

// MARK: - Demo questions (used when no deck selected)

enum DemoFlowQuestions {
    static let all: [FlowQuestion] = [
        FlowQuestion(
            question: "What does RAM stand for?",
            options: ["Random Access Memory", "Read Access Mode", "Runtime Array Module", "Rapid Action Memory"],
            correctIndex: 0,
            topic: "Tech",
            isMCQ: true
        ),
        FlowQuestion(
            question: "What planet is closest to the Sun?",
            options: ["Venus", "Earth", "Mercury", "Mars"],
            correctIndex: 2,
            topic: "Science",
            isMCQ: true
        ),
        FlowQuestion(
            question: "Type the answer: What gas do plants absorb?",
            options: ["carbon dioxide", "", "", ""],
            correctIndex: 0,
            topic: "Biology",
            isMCQ: false
        ),
        FlowQuestion(
            question: "Who wrote Romeo and Juliet?",
            options: ["Charles Dickens", "William Shakespeare", "Jane Austen", "Homer"],
            correctIndex: 1,
            topic: "Literature",
            isMCQ: true
        ),
        FlowQuestion(
            question: "What is 7 × 8?",
            options: ["54", "56", "63", "48"],
            correctIndex: 1,
            topic: "Math",
            isMCQ: true
        ),
        FlowQuestion(
            question: "Type the answer: What is H₂O?",
            options: ["water", "", "", ""],
            correctIndex: 0,
            topic: "Chemistry",
            isMCQ: false
        ),
    ]
}
