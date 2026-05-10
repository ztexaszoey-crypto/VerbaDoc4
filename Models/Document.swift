import Foundation
import SwiftData

@Model
final class Document {
    @Attribute(.unique) var id: String = UUID().uuidString
    var title: String
    var content: String
    var sourceType: SourceType
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \StudyItem.document)
    var studyItems: [StudyItem] = []
    
    init(title: String, content: String, sourceType: SourceType) {
        self.title = title
        self.content = content
        self.sourceType = sourceType
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum SourceType: String, Codable {
    case pdf = "PDF"
    case text = "Text"
    case image = "Image"
    case audio = "Audio"
    case url = "URL"
    case file = "File"
}
