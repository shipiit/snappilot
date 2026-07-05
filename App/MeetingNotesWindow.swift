import SwiftUI
import AppKit
import SnapCore

/// Everything produced for one meeting: the notes plus the raw transcript.
struct MeetingDoc {
    var title: String
    var date: Date
    var notes: MeetingNotes
    var lines: [TranscriptLine]
    var recordingURL: URL?

    /// Render the whole thing as portable Markdown.
    func markdown() -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
        var md = "# Meeting Notes — \(title)\n\(df.string(from: date))\n"
        if !notes.summary.isEmpty {
            md += "\n## Summary\n" + notes.summary.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !notes.tasks.isEmpty {
            md += "\n## Action Items\n" + notes.tasks.map { "- [ ] **\($0.owner):** \($0.text)" }.joined(separator: "\n") + "\n"
        }
        if !notes.keyPoints.isEmpty {
            md += "\n## Key Points\n" + notes.keyPoints.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !lines.isEmpty {
            md += "\n## Transcript\n" + lines.map { "**[\($0.stamp)] \($0.speaker):** \($0.text)" }.joined(separator: "\n\n") + "\n"
        }
        return md
    }
}

@MainActor
final class MeetingNotesWindowController: NSWindowController {
    private static var retained: [MeetingNotesWindowController] = []

    static func present(_ doc: MeetingDoc) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 780),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Meeting Notes"
        win.titlebarAppearsTransparent = true
        win.center()
        win.isReleasedWhenClosed = false
        let controller = MeetingNotesWindowController(window: win)
        win.contentView = NSHostingView(rootView: MeetingNotesView(doc: doc, onClose: {
            win.performClose(nil)
        }))
        win.delegate = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        retained.append(controller)
    }

    func windowWillClose(_ notification: Notification) {
        Self.retained.removeAll { $0 === self }
    }
}

extension MeetingNotesWindowController: NSWindowDelegate {}

private struct MeetingNotesView: View {
    @State private var doc: MeetingDoc
    let onClose: () -> Void
    @State private var done: Set<String> = []
    @State private var copied = false

    init(doc: MeetingDoc, onClose: @escaping () -> Void) {
        _doc = State(initialValue: doc)
        self.onClose = onClose
    }

    private var speakers: [String] { Array(Set(doc.lines.map { $0.speaker })).sorted() }

    private func renameSpeaker(_ from: String, to: String) {
        let n = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        for i in doc.lines.indices where doc.lines[i].speaker == from { doc.lines[i].speaker = n }
        for i in doc.notes.tasks.indices where doc.notes.tasks[i].owner == from { doc.notes.tasks[i].owner = n }
        // Keep the sidecar Markdown in sync with the renamed speakers.
        if let url = doc.recordingURL?.deletingPathExtension().appendingPathExtension("md") {
            try? doc.markdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func promptRename(_ current: String) -> String? {
        let alert = NSAlert(); alert.messageText = "Rename speaker"
        alert.informativeText = "Give “\(current)” a real name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = current == "You" ? current : ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if doc.notes.isEmpty && doc.lines.isEmpty {
                        emptyState
                    } else {
                        if !doc.notes.summary.isEmpty { summarySection }
                        if !doc.notes.tasks.isEmpty { tasksSection }
                        if !doc.notes.keyPoints.isEmpty { keyPointsSection }
                        if !doc.lines.isEmpty { transcriptSection }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.appBG)
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.headline)
                Text(doc.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !speakers.isEmpty {
                Menu {
                    ForEach(speakers, id: \.self) { sp in
                        Button("Rename “\(sp)”…") { if let n = promptRename(sp) { renameSpeaker(sp, to: n) } }
                    }
                } label: { Label("Speakers", systemImage: "person.crop.circle") }
                .fixedSize()
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(doc.markdown(), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
            } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
            Button { exportMarkdown() } label: { Label("Export", systemImage: "square.and.arrow.up") }
            if doc.recordingURL != nil {
                Button { NSWorkspace.shared.activateFileViewerSelecting([doc.recordingURL!]) } label: {
                    Label("Recording", systemImage: "video")
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var summarySection: some View {
        section("Summary", "text.alignleft") {
            ForEach(Array(doc.notes.summary.enumerated()), id: \.offset) { _, s in
                bullet(s)
            }
        }
    }

    private var tasksSection: some View {
        section("Action Items", "checklist") {
            ForEach(doc.notes.tasks) { task in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: done.contains(task.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done.contains(task.id) ? Color.accentColor : .secondary)
                        .onTapGesture {
                            if done.contains(task.id) { done.remove(task.id) } else { done.insert(task.id) }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.text)
                            .strikethrough(done.contains(task.id))
                            .foregroundStyle(done.contains(task.id) ? .secondary : .primary)
                        Text(task.owner).font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(speakerColor(task.owner).opacity(0.16), in: Capsule())
                    }
                }
            }
        }
    }

    private var keyPointsSection: some View {
        section("Key Points", "key.fill") {
            ForEach(Array(doc.notes.keyPoints.enumerated()), id: \.offset) { _, s in bullet(s) }
        }
    }

    private var transcriptSection: some View {
        section("Transcript", "text.bubble") {
            ForEach(doc.lines) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text(line.stamp).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.speaker).font(.caption.bold()).foregroundStyle(speakerColor(line.speaker))
                        Text(line.text).foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("No speech was recognized in this recording.")
                .foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func section<Content: View>(_ title: String, _ icon: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color.secondary).frame(width: 5, height: 5).padding(.top, 7)
            Text(text)
        }
    }

    private func speakerColor(_ name: String) -> Color {
        switch name {
        case "You": return .blue
        case "Participants": return .purple
        default: return .teal
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = doc.title.replacingOccurrences(of: " ", with: "-") + ".md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? doc.markdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
