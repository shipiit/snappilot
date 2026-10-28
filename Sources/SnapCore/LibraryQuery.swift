import Foundation

/// Which captures a gallery shows.
public enum CaptureFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case all, images, videos, text, meetings, favorites
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "All"
        case .images: return "Images"
        case .videos: return "Videos"
        case .text: return "Text (OCR)"
        case .meetings: return "Meetings"
        case .favorites: return "Favorites"
        }
    }
}

public enum CaptureSort: String, CaseIterable, Codable, Sendable, Identifiable {
    case newest, oldest, name, largest
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .name: return "Name"
        case .largest: return "Largest"
        }
    }
}

public enum LibraryQuery {
    /// Filter, search and sort captures. `hasMeetingNotes` reports whether a recording has a
    /// transcript (that lives in a sidecar file, so the caller answers it).
    public static func apply(_ records: [CaptureRecord], filter: CaptureFilter, sort: CaptureSort,
                             query: String, hasMeetingNotes: (CaptureRecord) -> Bool) -> [CaptureRecord] {
        let kept = records.filter { record in
            let inFilter: Bool
            switch filter {
            case .all: inFilter = true
            case .images: inFilter = record.kind == .image
            case .videos: inFilter = record.kind == .video
            case .text: inFilter = !record.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .meetings: inFilter = record.kind == .video && hasMeetingNotes(record)
            case .favorites: inFilter = record.favorite
            }
            return inFilter && CaptureLibrary.matches(record, query: query)
        }
        switch sort {
        case .newest: return kept.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return kept.sorted { $0.createdAt < $1.createdAt }
        case .name: return kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .largest: return kept.sorted { $0.width * $0.height > $1.width * $1.height }
        }
    }

    /// "Good morning" / "Good afternoon" / "Good evening" for an hour of the day (0–23).
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// First name from a full user name ("Rahul Raj" → "Rahul"); nil when there isn't one.
    public static func firstName(_ fullName: String) -> String? {
        fullName.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
