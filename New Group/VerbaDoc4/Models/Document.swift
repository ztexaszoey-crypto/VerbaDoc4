import Foundation
import SwiftData

enum SourceType: String, Codable, CaseIterable {
    case text, photoOCR, pdf

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .photoOCR: return "Photo (OCR)"
        case .pdf: return "PDF"
        }
    }

    var systemIcon: String {
        switch self {
        case .text: return "doc.text"
        case .photoOCR: return "camera.viewfinder"
        case .pdf: return "doc.richtext"
        }
    }
}

@Model
final class Document {
    var id: UUID
    var title: String
    var extractedText: String
    var sourceTypeRaw: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var studyItems: [StudyItem]? = []

    init(title: String, extractedText: String, sourceType: SourceType = .text) {
        self.id            = UUID()
        self.title         = title.trimmingCharacters(in: .whitespaces)
        self.extractedText = extractedText
        self.sourceTypeRaw = sourceType.rawValue
        self.createdAt     = Date()
    }

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .text }
        set { sourceTypeRaw = newValue.rawValue }
    }
}
