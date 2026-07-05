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
    @Published private(set) var collections: [Collection] = []
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var notes: [Note] = []

    let root: URL
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var collectionsURL: URL { root.appendingPathComponent("collections.json") }
    private var tasksURL: URL { root.appendingPathComponent("tasks.json") }
    private var notesURL: URL { root.appendingPathComponent("notes.json") }

    init(root: URL = CaptureLibrary.defaultRoot()) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder.snap.decode([CaptureRecord].self, from: data) {
            records = decoded.sorted { $0.createdAt > $1.createdAt }
        }
        if let data = try? Data(contentsOf: collectionsURL),
           let decoded = try? JSONDecoder.snap.decode([Collection].self, from: data) {
            collections = decoded.sorted { $0.createdAt > $1.createdAt }
        }
        if let data = try? Data(contentsOf: tasksURL),
           let decoded = try? JSONDecoder.snap.decode([TaskItem].self, from: data) {
            tasks = decoded
        }
        if let data = try? Data(contentsOf: notesURL),
           let decoded = try? JSONDecoder.snap.decode([Note].self, from: data) {
            notes = decoded
        }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder.snap.encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func persistCollections() {
        guard let data = try? JSONEncoder.snap.encode(collections) else { return }
        try? data.write(to: collectionsURL, options: .atomic)
    }

    // MARK: Collections

    @discardableResult
    func createCollection(name: String) -> Collection {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = Collection(id: UUID().uuidString, name: n.isEmpty ? "Untitled Collection" : n)
        collections.insert(c, at: 0)
        persistCollections()
        return c
    }

    func renameCollection(id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].name = n
        persistCollections()
    }

    func deleteCollection(id: String) {
        collections.removeAll { $0.id == id }
        persistCollections()
    }

    func addToCollection(_ collectionID: String, recordID: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }),
              !collections[idx].recordIDs.contains(recordID) else { return }
        collections[idx].recordIDs.insert(recordID, at: 0)
        persistCollections()
    }

    func removeFromCollection(_ collectionID: String, recordID: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].recordIDs.removeAll { $0 == recordID }
        persistCollections()
    }

    /// Records belonging to a collection, newest first, skipping any that were deleted.
    func records(in collection: Collection) -> [CaptureRecord] {
        collection.recordIDs.compactMap { id in records.first { $0.id == id } }
    }

    // MARK: Tasks (Kanban board)

    private func persistTasks() {
        guard let data = try? JSONEncoder.snap.encode(tasks) else { return }
        try? data.write(to: tasksURL, options: .atomic)
    }

    func tasks(in status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }.sorted { $0.order < $1.order }
    }

    private func nextOrder(in status: TaskStatus) -> Double {
        (tasks.filter { $0.status == status }.map { $0.order }.max() ?? 0) + 1
    }

    /// Next issue key, e.g. "SNAP-13".
    private func nextKey() -> String {
        let maxNum = tasks.compactMap { $0.key?.split(separator: "-").last.flatMap { Int($0) } }.max() ?? 0
        return "SNAP-\(maxNum + 1)"
    }

    @discardableResult
    func createTask(title: String, details: String = "", status: TaskStatus = .todo,
                    priority: TaskPriority = .none, owner: String? = nil, labels: [String]? = nil,
                    due: Date? = nil, imageFile: String? = nil, sourceMeetingID: String? = nil) -> TaskItem {
        var task = TaskItem(key: nextKey(), title: title, details: details, status: status,
                            priority: priority, owner: owner, labels: labels, due: due,
                            imageFile: imageFile, updatedAt: Date(), order: nextOrder(in: status),
                            sourceMeetingID: sourceMeetingID)
        task.history.append(TaskEvent(text: "Created in \(status.title)"))
        tasks.append(task)
        persistTasks()
        TaskNotifier.schedule(task)
        return task
    }

    /// Mutate a task in place, bump its updated time, persist.
    private func mutate(_ id: String, _ block: (inout TaskItem) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        block(&tasks[idx])
        tasks[idx].updatedAt = Date()
        persistTasks()
    }

    func setPriority(_ id: String, _ priority: TaskPriority) { mutate(id) { $0.priority = priority } }
    func setLabels(_ id: String, _ labels: [String]) { mutate(id) { $0.labels = labels.isEmpty ? nil : labels } }

    func addSubtask(_ id: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        mutate(id) { $0.subtasks = ($0.subtasks ?? []) + [SubTask(title: t)] }
    }
    func toggleSubtask(_ id: String, subID: String) {
        mutate(id) { task in
            guard var list = task.subtasks, let i = list.firstIndex(where: { $0.id == subID }) else { return }
            list[i].done.toggle(); task.subtasks = list
        }
    }
    func removeSubtask(_ id: String, subID: String) {
        mutate(id) { $0.subtasks?.removeAll { $0.id == subID } }
    }
    func updateSubtask(_ id: String, subID: String, title: String? = nil, details: String? = nil) {
        mutate(id) { task in
            guard var list = task.subtasks, let i = list.firstIndex(where: { $0.id == subID }) else { return }
            if let title { list[i].title = title }
            if let details { list[i].details = details }
            task.subtasks = list
        }
    }
    func addComment(_ id: String, author: String, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        mutate(id) { $0.comments = ($0.comments ?? []) + [TaskComment(author: author, text: t)] }
    }

    // MARK: Notes

    private func persistNotes() {
        guard let data = try? JSONEncoder.snap.encode(notes) else { return }
        try? data.write(to: notesURL, options: .atomic)
    }

    @discardableResult
    func createNote(title: String = "", body: String = "", folder: String? = nil) -> Note {
        let note = Note(title: title, body: body, folder: folder)
        notes.insert(note, at: 0)
        persistNotes()
        return note
    }

    /// Update a note's editable fields (title/body/folder/tags) and bump its timestamp.
    func updateNote(id: String, title: String? = nil, body: String? = nil, folder: String? = nil, tags: [String]? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { notes[idx].title = title }
        if let body { notes[idx].body = body }
        if let folder { notes[idx].folder = folder }
        if let tags { notes[idx].tags = tags }
        notes[idx].updatedAt = Date()
        persistNotes()
    }

    func deleteNote(id: String) { notes.removeAll { $0.id == id }; persistNotes() }

    func toggleNoteFavorite(id: String) { mutateNote(id) { $0.isFavorite.toggle() } }
    func toggleNotePinned(id: String) { mutateNote(id) { $0.isPinned.toggle() } }
    func toggleNoteArchived(id: String) { mutateNote(id) { $0.isArchived.toggle() } }

    @discardableResult
    func duplicateNote(id: String) -> Note? {
        guard let n = notes.first(where: { $0.id == id }) else { return nil }
        return createNote(title: n.title.isEmpty ? "" : "\(n.title) copy", body: n.body, folder: n.folder)
    }

    private func mutateNote(_ id: String, _ block: (inout Note) -> Void) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        block(&notes[idx]); notes[idx].updatedAt = Date(); persistNotes()
    }

    var noteFolders: [String] {
        Array(Set(notes.compactMap { $0.folder }.filter { !$0.isEmpty })).sorted { $0.lowercased() < $1.lowercased() }
    }

    func updateTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = task; t.updatedAt = Date()
        tasks[idx] = t
        persistTasks()
        TaskNotifier.schedule(t)
    }

    func moveTask(id: String, to status: TaskStatus) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }), tasks[idx].status != status else { return }
        var task = TaskBoard.move(tasks[idx], to: status)
        task.order = nextOrder(in: status)
        tasks[idx] = task
        persistTasks()
        TaskNotifier.schedule(task)      // cancels the reminder once done
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        persistTasks()
        TaskNotifier.cancel(id)
    }

    func task(_ id: String) -> TaskItem? { tasks.first { $0.id == id } }

    /// Copy an image/file into the library and attach it to a task.
    @discardableResult
    func addAttachment(to taskID: String, from url: URL) -> Bool {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }), let rel = attachImage(from: url) else { return false }
        var list = tasks[idx].attachments ?? []
        list.append(rel)
        tasks[idx].attachments = list
        tasks[idx].history.append(TaskEvent(text: "Attached \(url.lastPathComponent)"))
        persistTasks()
        return true
    }

    func removeAttachment(from taskID: String, _ relativePath: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].attachments?.removeAll { $0 == relativePath }
        if tasks[idx].imageFile == relativePath { tasks[idx].imageFile = nil }
        try? FileManager.default.removeItem(at: attachmentURL(relativePath))
        persistTasks()
    }

    /// Copy an image file into the library's attachments folder; returns its relative path.
    func attachImage(from url: URL) -> String? {
        let dir = root.appendingPathComponent("task-attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rel = "task-attachments/\(UUID().uuidString.prefix(8)).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
        let dest = root.appendingPathComponent(rel)
        do { try FileManager.default.copyItem(at: url, to: dest); return rel }
        catch { return nil }
    }

    func attachmentURL(_ relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    /// Import action items from all meeting notes into the board (skips already-imported ones).
    @discardableResult
    func importMeetingActionItems() -> Int {
        var added = 0
        for record in records where record.kind == .video && hasNotes(record) {
            guard let doc = loadNotes(for: record) else { continue }
            for task in doc.notes.tasks {
                let already = tasks.contains {
                    $0.sourceMeetingID == record.id && $0.title == task.text
                }
                if already { continue }
                createTask(title: task.text, details: "From “\(doc.title)”",
                           status: .todo, owner: task.owner, sourceMeetingID: record.id)
                added += 1
            }
        }
        return added
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

    // MARK: Meeting notes (sidecar next to the recording)

    func notesURL(for record: CaptureRecord) -> URL {
        fileURL(for: record).deletingPathExtension().appendingPathExtension("notes.json")
    }

    func hasNotes(_ record: CaptureRecord) -> Bool {
        FileManager.default.fileExists(atPath: notesURL(for: record).path)
    }

    func saveNotes(_ doc: MeetingDoc, for record: CaptureRecord) {
        guard let data = try? JSONEncoder.snap.encode(doc) else { return }
        try? data.write(to: notesURL(for: record), options: .atomic)
        objectWillChange.send()      // refresh Tasks / badges
    }

    func loadNotes(for record: CaptureRecord) -> MeetingDoc? {
        guard let data = try? Data(contentsOf: notesURL(for: record)) else { return nil }
        return try? JSONDecoder.snap.decode(MeetingDoc.self, from: data)
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
        var changed = false
        for i in collections.indices where collections[i].recordIDs.contains(record.id) {
            collections[i].recordIDs.removeAll { $0 == record.id }; changed = true
        }
        if changed { persistCollections() }
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
