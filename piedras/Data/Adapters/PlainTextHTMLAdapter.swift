import Foundation
import UIKit

enum PlainTextHTMLAdapter {
    static func html(from plainText: String) -> String {
        let normalized = normalizeLineEndings(in: plainText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return ""
        }

        let escaped = escapeHTML(normalized)
        let paragraphWrapped = escaped
            .replacingOccurrences(of: "\n\n", with: "</p><p>")
            .replacingOccurrences(of: "\n", with: "<br />")

        return "<p>\(paragraphWrapped)</p>"
    }

    static func plainText(from html: String) -> String {
        let normalizedHTML = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHTML.isEmpty else {
            return ""
        }

        if let data = normalizedHTML.data(using: .utf8),
           let attributedString = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            return normalizePlainText(attributedString.string)
        }

        let tagStripped = normalizedHTML
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        return normalizePlainText(tagStripped)
    }

    private static func normalizePlainText(_ text: String) -> String {
        normalizeLineEndings(in: text)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
