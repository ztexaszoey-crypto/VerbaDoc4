import Foundation
import PDFKit

enum PDFExtractor {
    static func extractText(from url: URL) -> String {
        guard let pdf = PDFDocument(url: url) else { return "" }
        var result = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let str = page.string {
                result += str + "\n"
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
