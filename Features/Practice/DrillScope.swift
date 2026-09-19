import Foundation

// MARK: - SwiftUI View init convention
//
// SwiftUI Views in this project use explicit `init(document:scope:…)`
// with `scope` defaulting to `.all`. Do NOT rely on synthesized
// memberwise inits — Swift 6's macro pipeline does not always emit
// them when property wrappers (@Environment, @ObservedObject,
// @StateObject) are present alongside stored properties. Every
// study-mode view in `Features/Practice/` follows this convention.
// See ExamModeView.init and StudyGuideView.init as the canonical
// implementations.
//
// **Shape asymmetry**: the four study-mode views (Flashcard, OpenAnswer,
// Exam, StudyGuide) are 2-param with `init(document: Document, scope:
// DrillScope = .all)`. PracticeModePickerView is 3-param with
// `init(document:scope: = .all, onSelect: @escaping (PracticeMode) -> Void)`
// because it carries a callback. **Only `scope` defaults; closure
// parameters stay required.**

enum DrillScope {
    case all
    case due
    case weak
    case topic(String)

    /// Returns items narrowed by this scope.
    ///
    /// DEPRECATED for view-level consumption: prefer
    /// `scope.items(in: document)` when reading from a Document — that
    /// typed parameter makes the self-referential trap
    /// (`private var items { scope.items(in: items) }`) a compile error.
    /// `filter(_:)` remains the right answer for queue-level filtering
    /// where you already hold a StudyItem collection in a local.
    @available(*, deprecated, renamed: "items(in:)", message: "Prefer scope.items(in: Document) when reading from a Document, or keep filter(_:) if you already have a StudyItem collection.")
    func filter(_ items: [StudyItem]) -> [StudyItem] {
        let now = Date()
        switch self {
        case .all:
            return items
        case .due:
            return items.filter { $0.nextReviewAt <= now }
        case .weak:
            return items.filter { $0.mastery < 50 }
        case .topic(let t):
            return items.filter { $0.topic == t }
        }
    }
}

// MARK: - Typed read for documents
//
// Returning `[StudyItem]` from `Document` (not from another `[StudyItem]`)
// is what makes the self-referential computed-property trap impossible:
// `private var items: [StudyItem] { scope.items(in: items) }` fails to
// type-check because `[StudyItem]` ≠ `Document`. Adopt this helper at
// every body-level route site that currently uses `scope.filter(document.studyItems)`
// so the cycle can't be reintroduced.

extension DrillScope {
    /// Returns `document.studyItems` narrowed by this scope.
    ///
    /// **Why this exists:** the typed `Document` parameter rejects the
    /// self-referential computed-property shape
    /// (`private var items { scope.filter(items) }`) at compile time,
    /// because `[StudyItem]` is not assignable to `Document`. Use this
    /// for any view-level scope read; reserve `filter(_:)` for queue-level
    /// consumers that already hold a pre-filtered `[StudyItem]` collection.
    func items(in document: Document) -> [StudyItem] {
        filter(document.studyItems)
    }
}
