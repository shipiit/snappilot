import SwiftUI
import AppKit
import SnapCore

private enum NoteMode: String, CaseIterable { case edit = "Edit", split = "Split", preview = "Preview" }
private enum NoteFilter: String, CaseIterable { case all = "All Notes", favorites = "Favorites", archive = "Archive" }

/// A modern Markdown notes workspace: a list of notes on the left, a live split editor
/// (raw Markdown ↔ rendered preview) in the middle, and an optional details panel (hidden
/// by default) on the right.
struct NotesView: View {
    @ObservedObject var library: LibraryStore

    @State private var selectedID: String?
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var mode: NoteMode = .split
    @State private var showInfo = false
    @State private var query = ""
    @State private var filter: NoteFilter = .all

    var body: some View {
        HStack(spacing: 0) {
            listPanel.frame(width: 258)
            Divider()
            editorPane
            if showInfo, selectedNote != nil {
                Divider()
                infoPanel.frame(width: 260)
            }
        }
        .background(Theme.appBG)
        .onAppear { if selectedID == nil { selectedID = filtered.first?.id; loadDraft() } }
        .onChange(of: selectedID) { loadDraft() }
        .onChange(of: draftBody) { persist() }
        .onChange(of: draftTitle) { persist() }
    }

    private var selectedNote: Note? { library.notes.first { $0.id == selectedID } }

    private var filtered: [Note] {
        library.notes
            .filter { note in
                switch filter {
                case .all: return !note.isArchived
                case .favorites: return note.isFavorite && !note.isArchived
                case .archive: return note.isArchived
                }
            }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
    }

    // MARK: List panel

    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 9).fill(taskHex("#5E6AD2")).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "note.text").foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notebook").font(.system(size: 15, weight: .bold))
                    Text("Markdown workspace").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)

            Button { newNote() } label: {
                Label("New note", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).padding(.horizontal, 14)

            ForEach(NoteFilter.allCases, id: \.self) { f in
                Button { filter = f; if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id; loadDraft() } } label: {
                    HStack {
                        Image(systemName: f == .all ? "square.stack" : f == .favorites ? "star" : "archivebox")
                        Text(f.rawValue)
                        Spacer()
                        Text("\(count(f))").foregroundStyle(.secondary)
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
                    ForEach(filtered) { note in noteRow(note) }
                    if filtered.isEmpty {
                        Text("No notes").font(.caption).foregroundStyle(.tertiary).padding(.top, 30)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(Theme.sidebarBG)
    }

    private func noteRow(_ note: Note) -> some View {
        Button { selectedID = note.id } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if note.isFavorite { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                }
                Text(note.excerpt).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(selectedID == note.id ? Theme.selectedNav : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isFavorite ? "Unfavorite" : "Favorite") { library.toggleNoteFavorite(id: note.id) }
            Button(note.isPinned ? "Unpin" : "Pin") { library.toggleNotePinned(id: note.id) }
            Button(note.isArchived ? "Unarchive" : "Archive") { library.toggleNoteArchived(id: note.id) }
            Button("Duplicate") { if let n = library.duplicateNote(id: note.id) { selectedID = n.id } }
            Divider()
            Button("Delete", role: .destructive) { deleteNote(note.id) }
        }
    }

    // MARK: Editor

    @ViewBuilder private var editorPane: some View {
        if let note = selectedNote {
            VStack(spacing: 0) {
                editorHeader(note)
                Divider()
                editorBody
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "note.text").font(.system(size: 48)).foregroundStyle(.tertiary)
                Text("Select a note or create a new one").foregroundStyle(.secondary)
                Button { newNote() } label: { Label("New note", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editorHeader(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Untitled note", text: $draftTitle).textFieldStyle(.plain).font(.title2.bold())
                Button { library.toggleNoteFavorite(id: note.id) } label: {
                    Image(systemName: note.isFavorite ? "star.fill" : "star").foregroundStyle(note.isFavorite ? .yellow : .secondary)
                }.buttonStyle(.borderless)
                Spacer()
                Picker("", selection: $mode) { ForEach(NoteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).fixedSize()
                Button { showInfo.toggle() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.borderless).help("Toggle details")
                menu(note)
            }
            Text("Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))  ·  \(note.wordCount) words · \(note.charCount) chars · \(note.readingMinutes) min read")
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
            Divider()
            Button("Delete note", role: .destructive) { deleteNote(note.id) }
        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
    }

    @ViewBuilder private var editorBody: some View {
        switch mode {
        case .edit:
            sourceEditor
        case .preview:
            preview
        case .split:
            HStack(spacing: 0) {
                sourceEditor
                Divider()
                preview
            }
        }
    }

    private var sourceEditor: some View {
        TextEditor(text: $draftBody)
            .font(.system(.body, design: .monospaced))
            .padding(14).scrollContentBackground(.hidden).background(Theme.appBG)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        ScrollView {
            MarkdownView(text: draftBody)
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
        .background(Theme.panelBG)
        .frame(maxWidth: .infinity)
    }

    // MARK: Info panel

    @ViewBuilder private var infoPanel: some View {
        if let note = selectedNote {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Note details").font(.headline)
                    infoLine("Status", note.isArchived ? "Archived" : "Active")
                    infoLine("Favorite", note.isFavorite ? "Yes" : "No")
                    infoLine("Created", note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    infoLine("Updated", note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    infoLine("Words", "\(note.wordCount)")
                    infoLine("Reading time", "\(note.readingMinutes) min")
                    Divider()
                    Button { if let n = library.duplicateNote(id: note.id) { selectedID = n.id } } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    Button { exportNote(note) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { deleteNote(note.id) } label: { Label("Delete", systemImage: "trash") }
                }
                .padding(18)
            }
            .background(Theme.sidebarBG)
        }
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption) }
    }

    // MARK: Actions

    private func count(_ f: NoteFilter) -> Int {
        switch f {
        case .all: return library.notes.filter { !$0.isArchived }.count
        case .favorites: return library.notes.filter { $0.isFavorite && !$0.isArchived }.count
        case .archive: return library.notes.filter { $0.isArchived }.count
        }
    }

    private func newNote() {
        let n = library.createNote(title: "", body: "# New note\n\nStart writing in **Markdown**…")
        filter = .all; selectedID = n.id; loadDraft()
    }

    private func loadDraft() {
        if let note = selectedNote { draftTitle = note.title; draftBody = note.body }
        else { draftTitle = ""; draftBody = "" }
    }

    private func persist() {
        guard let note = selectedNote, note.title != draftTitle || note.body != draftBody else { return }
        library.updateNote(id: note.id, title: draftTitle, body: draftBody)
    }

    private func deleteNote(_ id: String) {
        library.deleteNote(id: id)
        if selectedID == id { selectedID = filtered.first?.id; loadDraft() }
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
