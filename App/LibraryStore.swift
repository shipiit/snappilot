import AppKit
import CoreGraphics
import ImageIO
import SnapCore
import UniformTypeIdentifiers

/// Persists every capture to ~/Pictures/Snappilot, organized by month, and keeps a JSON
/// index (title + OCR text) so captures are searchable later.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var records: [CaptureRecord] = []

    let root: URL
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    init(root: URL = CaptureLibrary.defaultRoot()) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.snap.decode([CaptureRecord].self, from: data) else { return }
        records = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder.snap.encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Save a rendered PNG into the library and index it. Returns the saved record.
    @discardableResult
    func saveImage(_ image: CGImage, ocrText: String = "", title: String = "", date: Date = Date()) -> CaptureRecord? {
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        let rel = CaptureLibrary.relativePath(for: date, suffix: suffix, ext: "png")
        let fileURL = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard writePNG(image, to: fileURL) else { return nil }

        let stem = CaptureLibrary.stem(for: date, suffix: suffix)
        let record = CaptureRecord(id: stem, kind: .image, fileName: rel, createdAt: date,
                                   width: image.width, height: image.height,
                                   ocrText: ocrText,
                                   title: title.isEmpty ? defaultTitle(for: date) : title)
        records.insert(record, at: 0)
        persistIndex()
        return record
    }

    /// Move a finished recording into the library and index it.
    @discardableResult
    func saveVideo(from tempURL: URL, width: Int, height: Int, date: Date = Date()) -> CaptureRecord? {
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        let rel = CaptureLibrary.relativePath(for: date, suffix: suffix, ext: "mp4")
        let fileURL = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do { try FileManager.default.moveItem(at: tempURL, to: fileURL) }
        catch { try? FileManager.default.copyItem(at: tempURL, to: fileURL) }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let stem = CaptureLibrary.stem(for: date, suffix: suffix)
        let record = CaptureRecord(id: stem, kind: .video, fileName: rel, createdAt: date,
                                   width: width, height: height, ocrText: "",
                                   title: defaultTitle(for: date))
        records.insert(record, at: 0)
        persistIndex()
        return record
    }

    func fileURL(for record: CaptureRecord) -> URL {
        root.appendingPathComponent(record.fileName)
    }

    /// Overwrite an existing capture's file with a new (edited) image, updating size and
    /// moving it to the front of the library.
    func overwrite(id: String, image: CGImage) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        _ = writePNG(image, to: fileURL(for: records[idx]))
        records[idx].width = image.width
        records[idx].height = image.height
        let rec = records.remove(at: idx)
        records.insert(rec, at: 0)
        persistIndex()
    }

    /// Back-fill OCR text after a capture is already saved (so it can save instantly).
    func setOCRText(id: String, _ text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].ocrText = text
        persistIndex()
    }

    func toggleFavorite(id: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isFavorite = !(records[idx].isFavorite ?? false)
        persistIndex()
    }

    func addTag(_ tag: String, to id: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var tags = records[idx].tags ?? []
        guard !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        tags.append(t)
        records[idx].tags = tags
        persistIndex()
    }

    func removeTag(_ tag: String, from id: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].tags?.removeAll { $0 == tag }
        persistIndex()
    }

    /// All distinct tags across the library, sorted.
    var allTags: [String] {
        Array(Set(records.flatMap { $0.tagList })).sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Move a capture's file to the Trash and drop it from the index.
    func moveToTrash(_ record: CaptureRecord) {
        try? FileManager.default.trashItem(at: fileURL(for: record), resultingItemURL: nil)
        records.removeAll { $0.id == record.id }
        persistIndex()
    }

    var favorites: [CaptureRecord] { records.filter { $0.favorite } }

    func search(_ query: String) -> [CaptureRecord] {
        records.filter { CaptureLibrary.matches($0, query: query) }
    }

    private func defaultTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return "Capture \(f.string(from: date))"
    }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}

extension JSONEncoder {
    static var snap: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted]; return e
    }
}
extension JSONDecoder {
    static var snap: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}
