import Foundation

/// Where and how captures are stored on the Mac, and the metadata index that makes
/// them searchable (including by OCR'd text). Pure path/naming logic lives here so it
/// can be unit-tested without touching the filesystem.
public enum CaptureKind: String, Codable, Sendable {
    case image, video
}

/// One entry in the local library index.
public struct CaptureRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String            // stable filename stem, e.g. "2026-07-04_14-30-05_a1b2"
    public var kind: CaptureKind
    public var fileName: String      // relative to the library root, e.g. "2026/07/…​.png"
    public var createdAt: Date
    public var width: Int
    public var height: Int
    public var ocrText: String       // recognized text, for search ("" if none)
    public var title: String
    public var isFavorite: Bool?     // optional so old index files still decode

    public init(id: String, kind: CaptureKind, fileName: String, createdAt: Date,
                width: Int, height: Int, ocrText: String = "", title: String = "",
                isFavorite: Bool? = nil) {
        self.id = id; self.kind = kind; self.fileName = fileName; self.createdAt = createdAt
        self.width = width; self.height = height; self.ocrText = ocrText; self.title = title
        self.isFavorite = isFavorite
    }

    public var favorite: Bool { isFavorite ?? false }

    /// Uppercased file extension, e.g. "PNG" / "MP4".
    public var format: String { (fileName as NSString).pathExtension.uppercased() }
}

public enum CaptureLibrary {
    /// Default library root: ~/Pictures/Snappilot (visible, user-owned, easy to find).
    public static func defaultRoot() -> URL {
        let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pics.appendingPathComponent("Snappilot", isDirectory: true)
    }

    /// A YYYY/MM subfolder path (relative) for a capture created at `date`.
    public static func relativeFolder(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d/%02d", c.year ?? 0, c.month ?? 0)
    }

    /// A stable, sortable filename stem: "YYYY-MM-DD_HH-mm-ss_<suffix>".
    public static func stem(for date: Date, suffix: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d_%02d-%02d-%02d_%@",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, suffix)
    }

    /// Full relative file path for a capture: "YYYY/MM/<stem>.<ext>".
    public static func relativePath(for date: Date, suffix: String, ext: String,
                                    calendar: Calendar = .current) -> String {
        "\(relativeFolder(for: date, calendar: calendar))/\(stem(for: date, suffix: suffix, calendar: calendar)).\(ext)"
    }

    /// Case-insensitive search over title + OCR text.
    public static func matches(_ record: CaptureRecord, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return record.title.lowercased().contains(q) || record.ocrText.lowercased().contains(q)
    }
}
