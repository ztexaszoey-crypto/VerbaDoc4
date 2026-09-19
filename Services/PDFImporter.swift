import Foundation
import PDFKit

// MARK: - PDFImporter
//
// Extracts readable text from PDF files using Apple's PDFKit.
// No external dependency — PDFKit is part of iOS 11+.
//
// Handles:
//   - Text-based PDFs (most lecture slides, textbooks, papers)
//   - Password-protected PDFs (returns nil gracefully)
//   - Scanned/image PDFs (PDFKit returns empty — caller should route to VisionOCR)

enum PDFImporter {

    struct ExtractionResult {
        let text: String
        let pageCount: Int
        let isLikelyScanned: Bool   // true if very little text extracted per page
        let title: String?          // PDF metadata title if available
    }

    // MARK: - Extract from URL

    /// Extract text from a PDF file at the given URL.
    /// Returns nil if the file cannot be opened.
    static func extract(from url: URL) -> ExtractionResult? {
        guard let document = PDFDocument(url: url) else { return nil }
        return extract(from: document)
    }

    /// Extract text from PDF data (e.g. from a document picker).
    static func extract(from data: Data) -> ExtractionResult? {
        guard let document = PDFDocument(data: data) else { return nil }
        return extract(from: document)
    }

    // MARK: - Core extraction

    private static func extract(from document: PDFDocument) -> ExtractionResult? {
        let pageCount = document.pageCount
        guard pageCount > 0 else { return nil }

        var pages: [String] = []
        for i in 0..<pageCount {
            if let page = document.page(at: i),
               let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                pages.append(text)
            }
        }

        let fullText = pages.joined(separator: "\n\n")

        // Heuristic: if extracted text is very sparse, likely a scanned PDF
        let avgCharsPerPage = fullText.count / max(1, pageCount)
        let isLikelyScanned = avgCharsPerPage < 80

        // Clean up common PDF extraction artifacts
        let cleaned = cleanExtractedText(fullText)

        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No text extracted at all
            return ExtractionResult(
                text: "",
                pageCount: pageCount,
                isLikelyScanned: true,
                title: document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            )
        }

        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String

        return ExtractionResult(
            text: cleaned,
            pageCount: pageCount,
            isLikelyScanned: isLikelyScanned,
            title: title
        )
    }

    // MARK: - Text cleanup

    private static func cleanExtractedText(_ text: String) -> String {
        var result = text

        // Remove excessive whitespace / blank lines
        result = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
            .filter { line in
                // Drop lines that are just page numbers, headers with numbers, etc.
                if line.isEmpty { return true }              // keep blank lines as separators
                if line.count < 3 { return false }           // drop "1", "ii", etc.
                if line.allSatisfy({ $0.isNumber || $0 == " " }) { return false }
                return true
            }
            .joined(separator: "\n")

        // Collapse 3+ consecutive blank lines to 2
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Remove soft hyphens from line-wrapped words
        result = result.replacingOccurrences(of: "-\n", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
