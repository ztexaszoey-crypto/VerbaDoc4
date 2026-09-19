import Vision
import UIKit

// MARK: - VisionOCR
//
// On-device OCR using Apple's Vision framework (iOS 13+).
// No internet required. No API key. Runs entirely on-device.
//
// Handles:
//   - Handwritten notes (uses .accurate recognition level)
//   - Printed textbook pages
//   - Whiteboard photos
//   - Scanned PDFs (when PDFImporter returns isLikelyScanned = true)
//
// Language: auto-detected from device locale.
// Recognition level: .accurate (slower but much better for study content).

enum VisionOCR {

    struct OCRResult {
        let text: String
        let confidence: Float   // average confidence across recognized blocks
        let blockCount: Int     // number of text regions found
    }

    // MARK: - Recognize image

    /// Perform OCR on a UIImage. Returns nil if no text detected.
    static func recognize(_ image: UIImage) async -> OCRResult? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }

                var lines: [String] = []
                var totalConfidence: Float = 0

                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    totalConfidence += candidate.confidence
                }

                let fullText = lines.joined(separator: "\n")
                let avgConfidence = totalConfidence / Float(observations.count)

                guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: OCRResult(
                    text: cleanOCRText(fullText),
                    confidence: avgConfidence,
                    blockCount: observations.count
                ))
            }

            // Settings for study-content accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"]  // extend as needed

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Batch (multiple images)

    /// OCR multiple images (e.g., multiple pages photographed).
    /// Results are joined in order.
    static func recognize(_ images: [UIImage]) async -> OCRResult? {
        var allLines: [String] = []
        var totalConfidence: Float = 0
        var totalBlocks = 0

        for image in images {
            if let result = await recognize(image) {
                allLines.append(result.text)
                totalConfidence += result.confidence
                totalBlocks += result.blockCount
            }
        }

        guard !allLines.isEmpty else { return nil }
        return OCRResult(
            text: allLines.joined(separator: "\n\n"),
            confidence: totalConfidence / Float(images.count),
            blockCount: totalBlocks
        )
    }

    // MARK: - Text cleanup

    private static func cleanOCRText(_ text: String) -> String {
        // OCR sometimes splits mid-word on line breaks — rejoin short trailing fragments
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var buffer = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !buffer.isEmpty { result.append(buffer); buffer = "" }
                result.append("")
                continue
            }
            if !buffer.isEmpty {
                // If previous line ended mid-word (no punctuation), try to join
                let lastChar = buffer.last
                if lastChar != nil && !".!?:;,".contains(lastChar!) && buffer.count < 60 {
                    buffer += " " + trimmed
                    continue
                } else {
                    result.append(buffer)
                    buffer = trimmed
                }
            } else {
                buffer = trimmed
            }
        }
        if !buffer.isEmpty { result.append(buffer) }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
