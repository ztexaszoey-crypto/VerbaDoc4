import Foundation

// MARK: - StudyLaunch
//
// Identifiable launch struct used by `.fullScreenCover(item:)` so the
// dashboard launches study sessions through ONE strongly-typed pathway.
// The previous `if let doc = studyTarget` pattern inside
// `.fullScreenCover(isPresented:)` was prone to blank-screen races
// when SwiftUI briefly evaluated the closure before the @State
// mutation propagated. The item-based pattern is Apple's recommended
// API and always presents with a non-nil value at the moment the
// cover is shown.

struct StudyLaunch: Identifiable {
    let id = UUID()
    let document: Document
    let mode: PracticeMode
    /// Used by `.flashcard` and `.quizOpenAnswer`. Other modes ignore
    /// `scope`; callers should pass `.all` for non-card-modes.
    let scope: DrillScope
}

enum PracticeMode: Equatable {
    case flashcard
    case quizMultipleChoice
    case quizOpenAnswer
    case studyGuide

    var title: String {
        switch self {
        case .flashcard:          return "Flashcards"
        case .quizMultipleChoice: return "Multiple choice"
        case .quizOpenAnswer:     return "Open answer"
        case .studyGuide:         return "Study guide"
        }
    }

    var subtitle: String {
        switch self {
        case .flashcard:          return "Classic recall · swipe to grade"
        case .quizMultipleChoice: return "Test yourself with distractors"
        case .quizOpenAnswer:     return "Type your answer, then reveal"
        case .studyGuide:         return "Topic-organized review sheet"
        }
    }

    var systemIcon: String {
        switch self {
        case .flashcard:          return "rectangle.stack.fill"
        case .quizMultipleChoice: return "list.bullet.rectangle.fill"
        case .quizOpenAnswer:     return "keyboard.fill"
        case .studyGuide:         return "list.bullet.rectangle.portrait.fill"
        }
    }

    var requiresPro: Bool {
        self == .quizMultipleChoice
    }

    /// Generation-product counterpart. Wiring `GenerationProduct` into
    /// the picker means a tile's visual style AND the AI output type
    /// stay in sync: a quiz portal tile routes through the quiz builder,
    /// a study guide tile routes through the document builder. Callers
    /// that want to dispatch an AI generation can use this directly.
    var product: GenerationProduct {
        switch self {
        case .flashcard:          return .flashcards
        case .quizMultipleChoice: return .multipleChoice
        case .quizOpenAnswer:     return .openAnswer
        case .studyGuide:         return .studyGuide
        }
    }
}

// MARK: - StudyLaunchContext
//
// Pre-pick wrapper that the launcher (LibraryView / DocumentDetailView)
// passes into `PracticeModePickerView` to identify which document
// + drill scope the picker represents. Once the user picks a mode
// the picker callback turns this into a full `StudyLaunch`.

struct StudyLaunchContext: Identifiable {
    let id = UUID()
    let document: Document
    let scope: DrillScope
}
