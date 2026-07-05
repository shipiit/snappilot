import SwiftUI
import AppKit
import SnapCore

/// A Linear/Jira-style task board: columns per status, drag a card to change its status,
/// create tasks manually (title, details, owner, due date, image), and track history.
struct KanbanView: View {
    @ObservedObject var library: LibraryStore
    @State private var creating = false
    @State private var editing: TaskItem?
    @State private var dropTarget: TaskStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks").font(.title2.bold())
                    Text("Drag cards between columns to change status.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { library.importMeetingActionItems().pipe { n in
                    Toast.show(n > 0 ? "Imported \(n) task\(n == 1 ? "" : "s") from meetings" : "No new meeting tasks",
                               symbol: "square.and.arrow.down") } } label: {
                    Label("Import from Meetings", systemImage: "square.and.arrow.down")
                }.buttonStyle(.bordered)
                Menu {
                    Button("Copy checklist") { copyTasks() }
                    Button("Export .md") { exportTasks() }
                    Button("Add open tasks to Reminders") { remind() }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }.fixedSize()
                Button { creating = true } label: { Label("New Task", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TaskStatus.allCases) { column($0) }
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
        }
        .background(Theme.appBG)
        .sheet(isPresented: $creating) { TaskEditSheet(library: library, existing: nil) }
        .sheet(item: $editing) { task in TaskEditSheet(library: library, existing: task) }
    }

    private func column(_ status: TaskStatus) -> some View {
        let items = library.tasks(in: status)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(color(status)).frame(width: 8, height: 8)
                Text(status.title).font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            ForEach(items) { task in
                card(task)
                    .onDrag { NSItemProvider(object: task.id as NSString) }
                    .onTapGesture { editing = task }
            }
            if items.isEmpty {
                Text("Drop here").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 264, alignment: .top)
        .padding(10)
        .background(dropTarget == status ? color(status).opacity(0.12) : Theme.panelBG,
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(dropTarget == status ? color(status) : Theme.stroke, lineWidth: dropTarget == status ? 2 : 1))
        .onDrop(of: [.text], isTargeted: Binding(
            get: { dropTarget == status },
            set: { dropTarget = $0 ? status : (dropTarget == status ? nil : dropTarget) })) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let id = obj as? String else { return }
                    Task { @MainActor in library.moveTask(id: id, to: status) }
                }
            }
            return true
        }
    }

    private func card(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let file = task.imageFile, let img = NSImage(contentsOf: library.attachmentURL(file)) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 90).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 6) {
                if let owner = task.owner, !owner.isEmpty {
                    chip(owner, "person.fill", .secondary)
                }
                if let due = task.due {
                    chip(due.formatted(date: .abbreviated, time: .omitted), "calendar",
                         task.isOverdue ? .red : .secondary)
                }
                Spacer()
                if !task.history.isEmpty {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
    }

    private func chip(_ text: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private func color(_ status: TaskStatus) -> Color {
        switch status {
        case .backlog: return .gray
        case .todo: return .blue
        case .inProgress: return .orange
        case .done: return .green
        }
    }

    // MARK: Export

    private func tasksMarkdown() -> String {
        var md = "# Tasks\n"
        for status in TaskStatus.allCases {
            let items = library.tasks(in: status)
            guard !items.isEmpty else { continue }
            md += "\n## \(status.title)\n"
            for t in items {
                let box = status == .done ? "x" : " "
                let owner = (t.owner?.isEmpty == false) ? " (\(t.owner!))" : ""
                md += "- [\(box)] \(t.title)\(owner)\n"
            }
        }
        return md
    }

    private func copyTasks() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tasksMarkdown(), forType: .string)
        Toast.show("Tasks copied as a checklist", symbol: "checkmark")
    }

    private func exportTasks() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tasks.md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? tasksMarkdown().write(to: url, atomically: true, encoding: .utf8)
            Toast.show("Tasks exported", symbol: "square.and.arrow.up")
        }
    }

    private func remind() {
        let open = library.tasks.filter { $0.status != .done }
            .map { ($0.owner?.isEmpty == false ? "\($0.owner!): " : "") + $0.title }
        guard !open.isEmpty else { Toast.show("No open tasks to add", symbol: "checklist"); return }
        TaskExporter.addToReminders(open)
    }
}

private extension Int {
    /// Tiny helper so `importMeetingActionItems()` can react to its returned count inline.
    func pipe(_ f: (Int) -> Void) { f(self) }
}

/// Create or edit a task.
private struct TaskEditSheet: View {
    @ObservedObject var library: LibraryStore
    let existing: TaskItem?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var status: TaskStatus
    @State private var owner: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var imageFile: String?

    init(library: LibraryStore, existing: TaskItem?) {
        self.library = library
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _details = State(initialValue: existing?.details ?? "")
        _status = State(initialValue: existing?.status ?? .todo)
        _owner = State(initialValue: existing?.owner ?? "")
        _hasDue = State(initialValue: existing?.due != nil)
        _due = State(initialValue: existing?.due ?? Date())
        _imageFile = State(initialValue: existing?.imageFile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "New Task" : "Edit Task").font(.title3.bold())

            TextField("Title", text: $title).textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $details).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke))
            }

            HStack(spacing: 14) {
                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                }.fixedSize()
                TextField("Owner (optional)", text: $owner).textFieldStyle(.roundedBorder).frame(width: 180)
            }

            HStack(spacing: 10) {
                Toggle("Due date", isOn: $hasDue)
                if hasDue { DatePicker("", selection: $due, displayedComponents: .date).labelsHidden() }
                Spacer()
                Button { pickImage() } label: {
                    Label(imageFile == nil ? "Attach Image" : "Change Image", systemImage: "photo")
                }
                if imageFile != nil { Button(role: .destructive) { imageFile = nil } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless) }
            }

            if let file = imageFile, let img = NSImage(contentsOf: library.attachmentURL(file)) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let existing, !existing.history.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.caption).foregroundStyle(.secondary)
                    ForEach(existing.history.reversed()) { ev in
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(.tertiary)
                            Text(ev.text).font(.caption)
                            Text(ev.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                if existing != nil {
                    Button(role: .destructive) {
                        library.deleteTask(id: existing!.id); dismiss()
                    } label: { Label("Delete", systemImage: "trash") }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Create" : "Save") { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let rel = library.attachImage(from: url) {
            imageFile = rel
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let ownerVal = owner.trimmingCharacters(in: .whitespaces).isEmpty ? nil : owner
        let dueVal = hasDue ? due : nil
        if var task = existing {
            if task.status != status { task = TaskBoard.move(task, to: status) }
            task.title = t; task.details = details; task.owner = ownerVal
            task.due = dueVal; task.imageFile = imageFile
            library.updateTask(task)
        } else {
            library.createTask(title: t, details: details, status: status,
                               owner: ownerVal, due: dueVal, imageFile: imageFile)
        }
        dismiss()
    }
}
