import SwiftUI
import AppKit
import SnapCore

@MainActor
final class TaskDetailWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [String: TaskDetailWindowController] = [:]

    static func present(taskID: String, library: LibraryStore) {
        if let existing = open[taskID] { existing.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Task"
        win.titlebarAppearsTransparent = true
        win.center()
        win.isReleasedWhenClosed = false
        let controller = TaskDetailWindowController(window: win)
        win.contentView = NSHostingView(rootView:
            TaskDetailView(library: library, taskID: taskID) { win.performClose(nil) })
        win.delegate = controller
        controller.taskID = taskID
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        open[taskID] = controller
    }

    private var taskID: String = ""
    func windowWillClose(_ notification: Notification) { Self.open[taskID] = nil }
}

private enum DetailTab: String, CaseIterable { case activity = "Activity", comments = "Comments", files = "Files" }

private struct TaskDetailView: View {
    @ObservedObject var library: LibraryStore
    let taskID: String
    let onClose: () -> Void

    @State private var title: String
    @State private var details: String
    @State private var assignee: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var previewBody = true
    @State private var tab: DetailTab = .activity
    @State private var newSubtask = ""
    @State private var newComment = ""
    @State private var editingSub: SubTask?

    init(library: LibraryStore, taskID: String, onClose: @escaping () -> Void) {
        self.library = library; self.taskID = taskID; self.onClose = onClose
        let t = library.task(taskID)
        _title = State(initialValue: t?.title ?? "")
        _details = State(initialValue: t?.details ?? "")
        _assignee = State(initialValue: t?.owner ?? "")
        _hasDue = State(initialValue: t?.due != nil)
        _due = State(initialValue: t?.due ?? Date())
    }

    private var task: TaskItem? { library.task(taskID) }

    var body: some View {
        if let task {
            HStack(spacing: 0) {
                main(task).frame(maxWidth: .infinity)
                Divider()
                details(task).frame(width: 260)
            }
            .background(Theme.appBG)
            .onDisappear { save() }
            .sheet(item: $editingSub) { sub in
                SubtaskDetailSheet(library: library, taskID: taskID, subtask: sub)
            }
        } else {
            Text("This task was deleted.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Main column

    private func main(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Button { onClose() } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    if let key = task.key {
                        Text(key).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    statusPill(task)
                    Spacer()
                    Button { save(); Toast.show("Saved", symbol: "checkmark") } label: { Label("Save", systemImage: "checkmark") }
                    Button(role: .destructive) { library.deleteTask(id: taskID); onClose() } label: { Image(systemName: "trash") }
                }

                TextField("Title", text: $title).font(.title.bold()).textFieldStyle(.plain).onSubmit { save() }

                labelRow(task)
                descriptionSection
                subtasksSection(task)
                tabsSection(task)
            }
            .padding(24)
        }
    }

    private func statusPill(_ task: TaskItem) -> some View {
        HStack(spacing: 5) {
            Circle().fill(taskHex(task.status.colorHex)).frame(width: 7, height: 7)
            Text(task.status.title).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(taskHex(task.status.colorHex).opacity(0.16), in: Capsule())
    }

    private func labelRow(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            ForEach(task.labelList, id: \.self) { l in
                HStack(spacing: 3) {
                    Text(l).font(.caption2)
                    Button { library.setLabels(taskID, task.labelList.filter { $0 != l }) } label: { Image(systemName: "xmark").font(.system(size: 7)) }
                        .buttonStyle(.borderless)
                }
                .foregroundStyle(taskHex("#5E6AD2"))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(taskHex("#5E6AD2").opacity(0.18), in: Capsule())
            }
            Button { if let t = promptText("Add label") { library.setLabels(taskID, task.labelList + [t]) } } label: {
                Label("Label", systemImage: "plus").font(.caption2)
            }.buttonStyle(.borderless)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description").font(.headline)
                Spacer()
                Picker("", selection: $previewBody) { Text("Preview").tag(true); Text("Edit").tag(false) }
                    .pickerStyle(.segmented).fixedSize()
            }
            if previewBody {
                if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No description. Switch to Edit to add Markdown.").font(.callout).foregroundStyle(.tertiary)
                } else {
                    MarkdownView(text: details).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                MarkdownEditor(text: $details, placeholder: "Add a detailed description…", minHeight: 140)
            }
        }
    }

    private func subtasksSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subtasks").font(.headline)
                if task.subtasksTotal > 0 {
                    Text("\(task.subtasksDone) / \(task.subtasksTotal)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if task.subtasksTotal > 0 {
                ProgressView(value: Double(task.subtasksDone), total: Double(task.subtasksTotal))
                    .tint(taskHex("#5E6AD2"))
            }
            ForEach(task.subtaskList) { sub in
                HStack(spacing: 8) {
                    Image(systemName: sub.done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(sub.done ? Color.accentColor : .secondary)
                        .onTapGesture { library.toggleSubtask(taskID, subID: sub.id) }
                    Text(sub.title).strikethrough(sub.done).foregroundStyle(sub.done ? .secondary : .primary)
                    if !(sub.details ?? "").isEmpty {
                        Image(systemName: "text.alignleft").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button { editingSub = sub } label: { Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless).help("Open subtask")
                    Button { library.removeSubtask(taskID, subID: sub.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingSub = sub }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                TextField("Add subtask", text: $newSubtask).textFieldStyle(.plain)
                    .onSubmit { library.addSubtask(taskID, title: newSubtask); newSubtask = "" }
            }
        }
    }

    private func tabsSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).fixedSize()

            switch tab {
            case .activity:
                ForEach(task.history.reversed()) { ev in
                    activityRow(ev.text, ev.date)
                }
                if task.history.isEmpty { Text("No activity yet").font(.caption).foregroundStyle(.tertiary) }
            case .comments:
                ForEach(task.commentList) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(c.author).font(.caption.bold()); Text(c.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary) }
                        MarkdownView(text: c.text)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .trailing, spacing: 6) {
                    MarkdownEditor(text: $newComment, placeholder: "Add a comment… (Markdown supported)", minHeight: 60)
                    Button { library.addComment(taskID, author: "You", text: newComment); newComment = "" } label: {
                        Label("Comment", systemImage: "paperplane.fill")
                    }.buttonStyle(.borderedProminent)
                        .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            case .files:
                filesGrid(task)
            }
        }
    }

    private func activityRow(_ text: String, _ date: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
            Text(text).font(.callout)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func filesGrid(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { addAttachments() } label: { Label("Add file", systemImage: "paperclip") }.buttonStyle(.bordered)
            if task.files.isEmpty {
                Text("No files attached").font(.caption).foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(task.files, id: \.self) { rel in fileCell(rel) }
                }
            }
        }
    }

    private func fileCell(_ rel: String) -> some View {
        let url = library.attachmentURL(rel)
        let isImage = ["png","jpg","jpeg","gif","heic","tiff","bmp"].contains(url.pathExtension.lowercased())
        return ZStack(alignment: .topTrailing) {
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                Group {
                    if isImage, let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        VStack(spacing: 6) { Image(systemName: "doc.fill").font(.title2); Text(url.lastPathComponent).font(.caption2).lineLimit(1) }
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(height: 88).frame(maxWidth: .infinity).background(Theme.panelBG).clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Button { library.removeAttachment(from: taskID, rel) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.5)) }
                .buttonStyle(.plain).padding(4)
        }
    }

    // MARK: Details panel

    private func details(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Details").font(.headline)
                detailRow("Assignee", "person") {
                    TextField("Unassigned", text: $assignee).textFieldStyle(.roundedBorder)
                }
                detailRow("Status", "circle.dotted") {
                    Menu(task.status.title) { ForEach(TaskStatus.allCases) { s in Button(s.title) { library.moveTask(id: taskID, to: s) } } }
                        .menuStyle(.borderlessButton)
                }
                detailRow("Priority", "flag") {
                    Menu {
                        ForEach(TaskPriority.allCases) { p in Button(p.title) { library.setPriority(taskID, p) } }
                    } label: {
                        HStack(spacing: 5) { Image(systemName: task.priorityValue.symbol).foregroundStyle(taskHex(task.priorityValue.colorHex)); Text(task.priorityValue.title) }
                    }.menuStyle(.borderlessButton)
                }
                detailRow("Due date", "calendar") {
                    HStack { Toggle("", isOn: $hasDue).labelsHidden()
                        if hasDue { DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute]).labelsHidden() } }
                }
                Divider()
                metaLine("Created", task.createdAt)
                metaLine("Updated", task.updatedAt ?? task.createdAt)
            }
            .padding(20)
        }
        .background(Theme.sidebarBG)
    }

    private func detailRow<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func metaLine(_ title: String, _ date: Date) -> some View {
        HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
    }

    // MARK: Actions

    private func addAttachments() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { for url in panel.urls { library.addAttachment(to: taskID, from: url) } }
    }

    private func promptText(_ title: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = f; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let t = f.stringValue.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private func save() {
        guard var t = library.task(taskID) else { return }
        let nt = title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.title = nt.isEmpty ? t.title : nt
        t.details = details
        t.owner = assignee.trimmingCharacters(in: .whitespaces).isEmpty ? nil : assignee
        t.due = hasDue ? due : nil
        library.updateTask(t)
    }
}

/// A focused view of a single subtask: rename it, toggle done, and give it its own
/// Markdown description (Preview/Edit) — like opening a linked sub-issue.
private struct SubtaskDetailSheet: View {
    @ObservedObject var library: LibraryStore
    let taskID: String
    let subtask: SubTask
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var done: Bool
    @State private var preview = true

    init(library: LibraryStore, taskID: String, subtask: SubTask) {
        self.library = library; self.taskID = taskID; self.subtask = subtask
        _title = State(initialValue: subtask.title)
        _details = State(initialValue: subtask.details ?? "")
        _done = State(initialValue: subtask.done)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.accentColor : .secondary)
                    .onTapGesture { done.toggle() }
                Text("Subtask").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            TextField("Subtask title", text: $title).textFieldStyle(.plain).font(.title3.bold())

            HStack {
                Text("Description").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $preview) { Text("Preview").tag(true); Text("Edit").tag(false) }
                    .pickerStyle(.segmented).fixedSize()
            }
            if preview {
                if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No description. Switch to Edit to add Markdown.").font(.callout).foregroundStyle(.tertiary)
                } else {
                    MarkdownView(text: details).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                MarkdownEditor(text: $details, placeholder: "Describe this subtask…", minHeight: 140)
            }

            HStack {
                Button(role: .destructive) { library.removeSubtask(taskID, subID: subtask.id); dismiss() } label: {
                    Label("Delete", systemImage: "trash")
                }
                Spacer()
                Button("Done") { save(); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 460)
    }

    private func save() {
        library.updateSubtask(taskID, subID: subtask.id, title: title, details: details)
        if done != subtask.done { library.toggleSubtask(taskID, subID: subtask.id) }
    }
}
