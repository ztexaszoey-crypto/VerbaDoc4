import Foundation

// MARK: - WebImporter
//
// Fetches a URL and extracts readable text for card generation.
// Strips HTML tags, scripts, nav elements, and boilerplate.
// No third-party dependencies — pure URLSession + regex.
//
// Works well for:
//   - Wikipedia articles
//   - Blog posts / study guides
//   - News articles
//   - Documentation pages
//
// Does NOT work for:
//   - JavaScript-rendered SPAs (only gets the shell HTML)
//   - Login-gated content
//   - PDFs served inline (route to PDFImporter instead)

enum WebImporter {

    struct FetchResult {
        let text: String
        let title: String?
        let url: URL
        let wordCount: Int
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case noReadableContent
        case tooShort

        var errorDescription: String? {
            switch self {
            case .invalidURL:          return "That doesn't look like a valid URL."
            case .networkError(let e): return "Couldn't load the page: \(e.localizedDescription)"
            case .noReadableContent:   return "No readable text found on this page."
            case .tooShort:            return "Not enough content to generate cards."
            }
        }
    }

    // MARK: - Fetch

    static func fetch(urlString: String) async throws -> FetchResult {
        // Normalize URL
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        guard let url = URL(string: cleaned) else { throw FetchError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw FetchError.noReadableContent
            }
            data = d
        } catch let e as FetchError {
            throw e
        } catch {
            throw FetchError.networkError(error)
        }

        // Detect encoding (try UTF-8, then latin-1)
        let html: String
        if let s = String(data: data, encoding: .utf8) {
            html = s
        } else if let s = String(data: data, encoding: .isoLatin1) {
            html = s
        } else {
            throw FetchError.noReadableContent
        }

        let pageTitle = extractTitle(from: html)
        let text      = extractText(from: html)

        let wordCount = text.split(separator: " ").count
        guard wordCount > 50 else { throw FetchError.tooShort }

        return FetchResult(text: text, title: pageTitle, url: url, wordCount: wordCount)
    }

    // MARK: - HTML → Text

    private static func extractText(from html: String) -> String {
        var text = html

        // 1. Remove <script>, <style>, <nav>, <header>, <footer>, <aside> with their content
        let blockTags = ["script", "style", "nav", "header", "footer", "aside", "form", "iframe"]
        for tag in blockTags {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 2. Replace block-level tags with newlines
        let blockElements = ["p", "div", "li", "br", "h1", "h2", "h3", "h4", "h5", "h6",
                             "tr", "td", "th", "blockquote", "pre", "article", "section", "main"]
        for tag in blockElements {
            text = text.replacingOccurrences(
                of: "</\(tag)>",
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>",
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 3. Remove all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // 4. Decode common HTML entities
        text = decodeEntities(text)

        // 5. Collapse whitespace
        text = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        // 6. Collapse 3+ newlines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractTitle(from html: String) -> String? {
        let pattern = "<title[^>]*>([^<]+)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        return decodeEntities(String(html[range])).trimmingCharacters(in: .whitespaces)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
            "&laquo;": "«", "&raquo;": "»", "&hellip;": "…",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
            "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}"
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }
        // Numeric entities: &#123; or &#x7B;
        result = result.replacingOccurrences(
            of: "&#(\\d+);",
            with: "",
            options: .regularExpression
        )
        return result
    }
}
