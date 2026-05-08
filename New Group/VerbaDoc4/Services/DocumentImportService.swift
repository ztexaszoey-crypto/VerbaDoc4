import Foundation
import PDFKit
import UIKit
import Vision

enum DocumentImportError: LocalizedError {
    case invalidPDF
    case unreadableImage
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "We couldn't read that PDF."
        case .unreadableImage:
            return "We couldn't read that photo."
        case .noRecognizedText:
            return "No text was detected in the selected image."
        }
    }
}

enum DocumentImportService {
    static func extractText(fromPDFAt url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentImportError.invalidPDF
        }

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw DocumentImportError.invalidPDF
        }
        return text
    }

    static func extractText(from imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw DocumentImportError.unreadableImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard !text.isEmpty else {
                    continuation.resume(throwing: DocumentImportError.noRecognizedText)
                    return
                }

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
