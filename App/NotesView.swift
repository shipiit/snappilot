import SwiftUI
import AppKit
import SnapCore

private enum NoteMode: String, CaseIterable { case edit = "Edit", split = "Split", preview = "Preview" }
enum NoteFilter: String, CaseIterable { case all = "All Notes", favorites = "Favorites", archive = "Archive" }

/// The notes list, shown inside the app's main sidebar so the editor gets the full width.
struct NotesSidebar: View {
    @ObservedObject var library: LibraryStore
    @Binding var selectedID: String?
    let onExit: () -> Void
    @State private var query = ""
    @State private var filter: NoteFilter = .all

    private var filtered: [Note] { NotesLogic.filtered(library.notes, filter: filter, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { onExit() } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.borderless)
                Image(systemName: "note.text").foregroundStyle(taskHex("#5E6AD2"))
                Text("Notebook").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14)

            Button { newNote() } label: { Label("New note", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).padding(.horizontal, 12)

            ForEach(NoteFilter.allCases, id: \.self) { f in
                Button { filter = f; fixSelection() } label: {
                    HStack {
                        Image(systemName: f == .all ? "square.stack" : f == .favorites ? "star" : "archivebox")
                        Text(f.rawValue); Spacer()
                        Text("\(NotesLogic.count(library.notes, f))").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filter == f ? Theme.selectedNav : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 10)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search notes", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(7).background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)

            Divider().padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { note in row(note) }
                    if filtered.isEmpty { Text("No notes").font(.caption).foregroundStyle(.tertiary).padding(.top, 30) }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        Button { selectedID = note.id } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if note.isFavorite { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                }
                Text(note.excerpt).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedID == note.id ? Theme.selectedNav : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isFavorite ? "Unfavorite" : "Favorite") { library.toggleNoteFavorite(id: note.id) }
            Button(note.isPinned ? "Unpin" : "Pin") { library.toggleNotePinned(id: note.id) }
            Button(note.isArchived ? "Unarchive" : "Archive") { library.toggleNoteArchived(id: note.id) }
            Button("Duplicate") { if let n = library.duplicateNote(id: note.id) { selectedID = n.id } }
            Divider()
            Button("Delete", role: .destructive) { library.deleteNote(id: note.id); fixSelection() }
        }
    }

    private func newNote() {
        let n = library.createNote(title: "", body: "# New note\n\nStart writing in **Markdown**…")
        filter = .all; selectedID = n.id
    }
    private func fixSelection() {
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
    }
}

enum NotesLogic {
    static func filtered(_ notes: [Note], filter: NoteFilter, query: String) -> [Note] {
        notes.filter { note in
            switch filter {
            case .all: return !note.isArchived
            case .favorites: return note.isFavorite && !note.isArchived
            case .archive: return note.isArchived
            }
        }
        .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
        .sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
    }
    static func count(_ notes: [Note], _ f: NoteFilter) -> Int {
        switch f {
        case .all: return notes.filter { !$0.isArchived }.count
        case .favorites: return notes.filter { $0.isFavorite && !$0.isArchived }.count
        case .archive: return notes.filter { $0.isArchived }.count
        }
    }
}

/// The note editor (live split Markdown ↔ preview) plus an optional details panel.
struct NotesView: View {
    @ObservedObject var library: LibraryStore
    @Binding var selectedID: String?

    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var mode: NoteMode = .split
    @State private var showInfo = false
    @State private var saveWork: DispatchWorkItem?

    private var selectedNote: Note? { library.notes.first { $0.id == selectedID } }

    var body: some View {
        Group {
            if let note = selectedNote {
                HStack(spacing: 0) {
                    VStack(spacing: 0) { header(note); Divider(); editorBody }
                        .frame(maxWidth: .infinity)
                    if showInfo { Divider(); infoPanel(note).frame(width: 250) }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "note.text").font(.system(size: 48)).foregroundStyle(.tertiary)
                    Text("Select a note, or create one from the sidebar").foregroundStyle(.secondary)
                    Button { let n = library.createNote(body: "# New note\n\n"); selectedID = n.id } label: {
                        Label("New note", systemImage: "plus")
                    }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.appBG)
        .onAppear { loadDraft() }
        .onChange(of: selectedID) { loadDraft() }
        .onChange(of: draftBody) { persist() }
        .onChange(of: draftTitle) { persist() }
    }

    private func header(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Untitled note", text: $draftTitle).textFieldStyle(.plain).font(.title2.bold())
                Button { library.toggleNoteFavorite(id: note.id) } label: {
                    Image(systemName: note.isFavorite ? "star.fill" : "star").foregroundStyle(note.isFavorite ? .yellow : .secondary)
                }.buttonStyle(.borderless)
                Spacer()
                Button { pasteImage() } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.borderless).help("Paste image from clipboard (⌘⇧V)")
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button { insertImage(note) } label: { Image(systemName: "photo") }.buttonStyle(.borderless).help("Insert image")
                Picker("", selection: $mode) { ForEach(NoteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).fixedSize()
                Button { showInfo.toggle() } label: { Image(systemName: "sidebar.right") }.buttonStyle(.borderless).help("Toggle details")
                menu(note)
            }
            Text("Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))  ·  \(note.wordCount) words · \(note.charCount) chars · \(note.readingMinutes) min read")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func menu(_ note: Note) -> some View {
        Menu {
            Button(note.isPinned ? "Unpin note" : "Pin note") { library.toggleNotePinned(id: note.id) }
            Button(note.isArchived ? "Unarchive note" : "Archive note") { library.toggleNoteArchived(id: note.id) }
            Button("Duplicate note") { if let n = library.duplicateNote(id: note.id) { selectedID = n.id } }
            Divider()
            Button("Copy markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.body, forType: .string); Toast.show("Copied", symbol: "checkmark") }
            Button("Export markdown") { exportNote(note) }
            Button("Insert image") { insertImage(note) }
            Divider()
            Button("Delete note", role: .destructive) { library.deleteNote(id: note.id); selectedID = nil }
        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
    }

    @ViewBuilder private var editorBody: some View {
        switch mode {
        case .edit: sourceEditor
        case .preview: preview
        case .split: HStack(spacing: 0) { sourceEditor; Divider(); preview }
        }
    }

    private var sourceEditor: some View {
        TextEditor(text: $draftBody)
            .font(.system(.body, design: .monospaced))
            .padding(14).scrollContentBackground(.hidden).background(Theme.appBG)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, ["png","jpg","jpeg","gif","heic","tiff"].contains(url.pathExtension.lowercased()) else { return }
                        Task { @MainActor in attach(url) }
                    }
                }
                return true
            }
    }

    private var preview: some View {
        ScrollView { MarkdownView(text: draftBody).frame(maxWidth: .infinity, alignment: .leading).padding(18) }
            .background(Theme.panelBG).frame(maxWidth: .infinity)
    }

    private func infoPanel(_ note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Note details").font(.headline)
                info("Status", note.isArchived ? "Archived" : "Active")
                info("Favorite", note.isFavorite ? "Yes" : "No")
                info("Created", note.createdAt.formatted(date: .abbreviated, time: .shortened))
                info("Updated", note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                info("Words", "\(note.wordCount)")
                info("Reading time", "\(note.readingMinutes) min")
                Divider()
                Button { if let n = library.duplicateNote(id: note.id) { selectedID = n.id } } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                Button { exportNote(note) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { library.deleteNote(id: note.id); selectedID = nil } label: { Label("Delete", systemImage: "trash") }
            }.padding(18)
        }.background(Theme.sidebarBG)
    }

    private func info(_ t: String, _ v: String) -> some View {
        HStack { Text(t).font(.caption).foregroundStyle(.secondary); Spacer(); Text(v).font(.caption) }
    }

    // MARK: Actions

    private func loadDraft() {
        if let note = selectedNote { draftTitle = note.title; draftBody = note.body }
        else { draftTitle = ""; draftBody = "" }
    }
    /// Debounced save — waits ~0.6s after the last keystroke so we don't rewrite the file
    /// on every character.
    private func persist() {
        guard let note = selectedNote, note.title != draftTitle || note.body != draftBody else { return }
        saveWork?.cancel()
        let id = note.id, title = draftTitle, body = draftBody
        let work = DispatchWorkItem { library.updateNote(id: id, title: title, body: body) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
    private func insertImage(_ note: Note) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { attach(url) }
    }
    private func attach(_ url: URL) {
        guard let rel = library.attachImage(from: url) else { return }
        insertImageMarkdown(name: url.deletingPathExtension().lastPathComponent, rel: rel)
    }

    /// Paste an image (or image file) from the clipboard into the note.
    private func pasteImage() {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first, let rel = library.saveAttachment(image: image) {
            insertImageMarkdown(name: "pasted-image", rel: rel)
            Toast.show("Image pasted", symbol: "photo")
        } else if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let url = urls.first,
                  ["png","jpg","jpeg","gif","heic","tiff"].contains(url.pathExtension.lowercased()) {
            attach(url)
        } else {
            Toast.show("No image on the clipboard", symbol: "clipboard")
        }
    }

    /// Insert image Markdown with a default width (edit the `|480` number to resize).
    private func insertImageMarkdown(name: String, rel: String) {
        let fileURL = library.attachmentURL(rel)
        draftBody += "\n\n![\(name)|480](\(fileURL.absoluteString))\n"
    }
    private func exportNote(_ note: Note) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (note.title.isEmpty ? "note" : note.title).replacingOccurrences(of: " ", with: "-") + ".md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? note.body.write(to: url, atomically: true, encoding: .utf8)
            Toast.show("Note exported", symbol: "square.and.arrow.up")
        }
    }
}
