import Foundation
import SwiftData

@Model
final class Document {
    @Attribute(.unique) var id: String = UUID().uuidString
    var title: String = ""
    var content: String = ""
    var sourceType: SourceType = SourceType.text
    var isArchived: Bool = false
    var examDate: Date? = nil
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade) var studyItems: [StudyItem] = []

    /// Topics within this Document. Apple canonical SwiftData pattern:
    /// the parent's collection side carries BOTH `deleteRule:` AND
    /// `inverse:` (i.e. Library.books → \Book.library); the to-one
    /// child link is a plain property. Cascade rule here means:
    /// `Document.delete → cascade Topic.delete`. Inverse declaration
    /// makes the bidirectional graph explicit instead of relying on
    /// SwiftData type-inference — protects against silent regressions
    /// across iOS minor versions.
    @Relationship(deleteRule: .cascade, inverse: \Topic.document) var topics: [Topic] = []

    /// Study sessions scoped to this Document. Mirrors the same
    /// Apple canonical pattern as topics: cascade + explicit inverse
    /// on the parent's collection side. Brief §21 demands no orphan
    /// session rows after Document deletion.
    @Relationship(deleteRule: .cascade, inverse: \StudySessionEntity.document) var studySessions: [StudySessionEntity] = []

    init(title: String, content: String, sourceType: SourceType = .text) {
        self.id = UUID().uuidString
        self.title = title
        self.content = content
        self.sourceType = sourceType
        self.isArchived = false
        self.examDate = nil
        self.createdAt = Date()
        self.studyItems = []
        self.topics = []
        self.studySessions = []
    }

    enum SourceType: String, Codable {
        case text, pdf, image, url, audio

        var systemIcon: String {
            switch self {
            case .text:  return "doc.text"
            case .pdf:   return "doc.richtext"
            case .image: return "photo"
            case .url:   return "link"
            case .audio: return "waveform"
            }
        }

        var displayName: String {
            switch self {
            case .text:  return "text"
            case .pdf:   return "PDF"
            case .image: return "image"
            case .url:   return "web"
            case .audio: return "audio"
            }
        }
    }
}
