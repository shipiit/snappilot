import Foundation

/// A Markdown note in the Notes workspace.
public struct Note: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var folder: String?
    public var tags: [String]?
    public var isFavorite: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String = "", body: String = "",
                folder: String? = nil, tags: [String]? = nil, isFavorite: Bool = false,
                isPinned: Bool = false, isArchived: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.body = body; self.folder = folder
        self.tags = tags; self.isFavorite = isFavorite; self.isPinned = isPinned
        self.isArchived = isArchived; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var displayTitle: String { title.isEmpty ? "Untitled note" : title }
    public var tagList: [String] { tags ?? [] }
    public var wordCount: Int { NoteText.wordCount(body) }
    public var charCount: Int { body.count }
    public var readingMinutes: Int { max(1, Int((Double(wordCount) / 200.0).rounded(.up))) }
    public var excerpt: String { NoteText.excerpt(body) }
}

public enum NoteText {
    public static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    /// A one-line, Markdown-stripped preview of the body (skips the title/heading line).
    public static func excerpt(_ body: String) -> String {
        for raw in body.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") { continue }             // skip heading/title lines
            while line.hasPrefix(">") || line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix(" ") {
                line.removeFirst()
            }
            line = line.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return String(line.prefix(120)) }
        }
        return "No additional text"
    }

    /// Derive a title from the first non-empty line if the user hasn't set one.
    public static func inferTitle(_ body: String) -> String {
        for raw in body.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return String(line.prefix(80)) }
        }
        return ""
    }
}
