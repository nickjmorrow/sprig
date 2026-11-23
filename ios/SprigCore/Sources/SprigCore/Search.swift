import Foundation
import GRDB

/// Full-text search inside one tab: every word of the query must appear somewhere in the
/// story's title, author, site, excerpt or article text, ignoring case, accents and markup.
enum Search {
    private static let fields = ["title", "author", "site", "excerpt", "contentHtml"]

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The tab's stories that match every term, each with the passage of its article (or
    /// excerpt) around the first match, if the match is there and not only in the title.
    /// SQL's LIKE narrows the rows cheaply; the check on the plain text then drops matches
    /// that were only inside tags.
    static func matches(_ db: Database, location: Location, terms: [String]) throws -> [String: String?] {
        var request = Item
            .select(fields.map { Column($0) } + [Column("id")])
            .filter(Column("location") == location.rawValue && Column("deleted") == false)
        for term in terms {
            let pattern = "%" + escapeLike(term) + "%"
            var matches = fields.map { Column($0).like(pattern, escape: "\\") }
            // Article bodies store "&" and "<" as entities, so look for that spelling there too.
            let htmlPattern = "%" + escapeLike(escapeHTML(term)) + "%"
            if htmlPattern != pattern { matches.append(Column("contentHtml").like(htmlPattern, escape: "\\")) }
            request = request.filter(matches.joined(operator: .or))
        }
        var found: [String: String?] = [:]
        for row in try request.asRequest(of: Row.self).fetchAll(db) {
            let body = plainText(fromHTML: row["contentHtml"] ?? "")
            let excerpt: String = row["excerpt"] ?? ""
            let text = fields.dropLast().map { row[$0] ?? "" }.joined(separator: "\n") + "\n" + body
            guard terms.allSatisfy({ text.range(of: $0, options: matchOptions) != nil }) else { continue }
            found[row["id"]] = passage(in: body, around: terms) ?? passage(in: excerpt, around: terms)
        }
        return found
    }

    static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let wordsBefore = 8
    private static let passageLength = 220

    /// A stretch of text starting a few words before the first term found, on one line.
    static func passage(in text: String, around terms: [String]) -> String? {
        let firstMatch = terms.compactMap { text.range(of: $0, options: matchOptions) }.min { $0.lowerBound < $1.lowerBound }
        guard let firstMatch else { return nil }
        let wordsBeforeMatch = text[..<firstMatch.lowerBound].suffix(passageLength).split(whereSeparator: \.isWhitespace)
        let before = wordsBeforeMatch.suffix(wordsBefore)
        let after = text[firstMatch.lowerBound...].prefix(passageLength * 2).split(whereSeparator: \.isWhitespace)
        var passage = (before + after).joined(separator: " ")
        if passage.count > passageLength {
            passage = String(passage.prefix(passageLength))
            if let lastSpace = passage.lastIndex(of: " ") { passage = String(passage[..<lastSpace]) }
            passage += "…"
        }
        return wordsBeforeMatch.count > wordsBefore ? "…" + passage : passage
    }

    private static func escapeLike(_ term: String) -> String {
        term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func escapeHTML(_ term: String) -> String {
        term.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let entities = [
        "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&mdash;": "—", "&ndash;": "–",
    ]

    static func plainText(fromHTML html: String) -> String {
        var text = html.replacing(/<[^>]*>/, with: " ")
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacing(/&#(x?)([0-9a-fA-F]+);/) { match in
            let value = UInt32(match.output.2, radix: match.output.1.isEmpty ? 10 : 16)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.output.0)
        }
        // Last, so "&amp;lt;" stays the literal text "&lt;".
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }
}
