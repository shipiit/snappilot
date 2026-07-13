import SwiftUI
import AppKit
import SnapCore
import UniformTypeIdentifiers

/// A Linear-style task board: columns per status, colored issue-key chips, priority,
/// subtask progress, assignee avatars, and drag-to-change-status.
enum BoardViewMode: String, CaseIterable { case kanban = "Kanban", list = "List" }

struct KanbanView: View {
    @ObservedObject var library: LibraryStore
    @State private var creating = false
    @State private var dropTarget: TaskStatus?
    @State private var mode: BoardViewMode = .kanban

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if mode == .kanban {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(TaskStatus.allCases) { column($0) }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }
            } else {
                listView
            }
        }
        .background(Theme.appBG)
        .sheet(isPresented: $creating) { CreateTaskSheet(library: library) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Roadmap").font(.title2.bold())
                    Text("Track and manage work across the board").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("From meetings") {
                        let n = library.importMeetingActionItems()
                        Toast.show(n > 0 ? "Imported \(n) task\(n == 1 ? "" : "s") from meetings"
                                         : "No meeting action items yet — record a meeting, then generate its notes.",
                                   symbol: n > 0 ? "square.and.arrow.down" : "info.circle")
                    }
                    Button("From file… (Markdown / text)") { importFromFile() }
                    Divider()
                    Button("Save a sample format…") { saveSampleFormat() }
                } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .fixedSize()
                    .help("Import tasks from your meetings, or upload a Markdown / text checklist")
                Menu {
                    Button("Copy checklist") { copyTasks() }
                    Button("Export .md") { exportTasks() }
                    Button("Add open tasks to Reminders") { remind() }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }.fixedSize()
                Button { creating = true } label: { Label("New task", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            Picker("", selection: $mode) {
                ForEach(BoardViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0 == .kanban ? "square.grid.2x2" : "list.bullet").tag($0) }
            }.pickerStyle(.segmented).fixedSize()
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private func column(_ status: TaskStatus) -> some View {
        let items = library.tasks(in: status)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(taskHex(status.colorHex)).frame(width: 9, height: 9)
                Text(status.title).font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { creating = true } label: { Image(systemName: "plus").font(.system(size: 11)) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(items) { task in
                card(task)
                    .onDrag { NSItemProvider(object: task.id as NSString) }
                    .onTapGesture { TaskDetailWindowController.present(taskID: task.id, library: library) }
            }
            Button { creating = true } label: {
                Label("Add task", systemImage: "plus").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.borderless).padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .frame(width: 272, alignment: .top)
        .padding(10)
        .background(dropTarget == status ? taskHex(status.colorHex).opacity(0.10) : Theme.panelBG,
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(dropTarget == status ? taskHex(status.colorHex) : Theme.stroke, lineWidth: dropTarget == status ? 2 : 1))
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
        VStack(alignment: .leading, spacing: 9) {
            Text(task.title).font(.system(size: 13, weight: .medium))
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let key = task.key {
                    Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(taskHex(task.status.colorHex))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(taskHex(task.status.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                }
                if task.priorityValue != .none {
                    Image(systemName: task.priorityValue.symbol).font(.system(size: 10))
                        .foregroundStyle(taskHex(task.priorityValue.colorHex))
                }
                ForEach(task.labelList.prefix(2), id: \.self) { l in
                    Text(l).font(.system(size: 9, weight: .medium)).foregroundStyle(taskHex("#5E6AD2"))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(taskHex("#5E6AD2").opacity(0.18), in: Capsule())
                }
            }
            HStack(spacing: 10) {
                if let owner = task.owner, !owner.isEmpty { avatar(owner) }
                if task.commentList.count > 0 {
                    metric("bubble.left", "\(task.commentList.count)")
                }
                if task.subtasksTotal > 0 {
                    metric("checklist", "\(task.subtasksDone)/\(task.subtasksTotal)")
                }
                Spacer()
                if let due = task.due {
                    Text(due.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10)).foregroundStyle(task.isOverdue ? .red : .secondary)
                }
            }
            if task.subtasksTotal > 0 { progressBar(task) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
    }

    private func metric(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10))
        }.foregroundStyle(.secondary)
    }

    private func progressBar(_ task: TaskItem) -> some View {
        let progress = task.subtasksTotal > 0 ? Double(task.subtasksDone) / Double(task.subtasksTotal) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.stroke).frame(height: 4)
                Capsule().fill(taskHex(task.status.colorHex)).frame(width: max(0, geo.size.width * progress), height: 4)
            }
        }.frame(height: 4)
    }

    private func avatar(_ name: String) -> some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        let palette = ["#5E6AD2", "#3FB950", "#E5484D", "#E2A03F", "#D177E0", "#0EA5E9"]
        let color = taskHex(palette[abs(name.hashValue) % palette.count])
        return Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 22, height: 22).background(color, in: Circle())
    }

    // MARK: List view

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(TaskStatus.allCases) { status in
                    let items = library.tasks(in: status)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 7) {
                                Circle().fill(taskHex(status.colorHex)).frame(width: 9, height: 9)
                                Text(status.title).font(.system(size: 13, weight: .semibold))
                                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            ForEach(items) { task in
                                listRow(task)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func listRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            if task.priorityValue != .none {
                Image(systemName: task.priorityValue.symbol).font(.system(size: 11))
                    .foregroundStyle(taskHex(task.priorityValue.colorHex)).frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }
            if let key = task.key {
                Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(taskHex(task.status.colorHex))
                    .frame(width: 64, alignment: .leading)
            }
            Text(task.title).font(.system(size: 13)).lineLimit(1)
            Spacer()
            ForEach(task.labelList.prefix(2), id: \.self) { l in
                Text(l).font(.system(size: 9, weight: .medium)).foregroundStyle(taskHex("#5E6AD2"))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(taskHex("#5E6AD2").opacity(0.18), in: Capsule())
            }
            if task.subtasksTotal > 0 { metric("checklist", "\(task.subtasksDone)/\(task.subtasksTotal)") }
            if task.commentList.count > 0 { metric("bubble.left", "\(task.commentList.count)") }
            if let due = task.due {
                Text(due.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 10)).foregroundStyle(task.isOverdue ? .red : .secondary).frame(width: 48, alignment: .trailing)
            }
            if let owner = task.owner, !owner.isEmpty { avatar(owner) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { TaskDetailWindowController.present(taskID: task.id, library: library) }
    }

    // MARK: Import from file

    /// The import file format, as a ready-to-edit sample (simple + detailed).
    private static let sampleFormat = """
    # Simple tasks (one line each)

    ## To do
    - [ ] Prepare the demo
    - Priya: Review the pull request

    ## Done
    - [x] Ship v0.1.8

    # Detailed tasks (fields indented under each task)

    - Implement the task detail page
        status: In progress
        owner: Rahul
        priority: High
        due: 2026-07-20
        labels: frontend, ui
        description: Build a clean, modern detail page with subtasks and comments.
        subtasks:
        - [x] Design layout
        - [x] Build header
        - [ ] Add comments feed
        - [ ] Attachments viewer

    - Fix the meeting transcription bug
        owner: Rahul
        priority: Urgent
        due: 2026-07-18
        labels: bug
        subtasks:
        - [ ] Repro on a long video
        - [ ] Ship the fix

    # Notes on the format:
    # • A top-level "- " line starts a task (its text is the title).
    # • Indent (spaces) the field lines under it:
    #     status:      To do | In progress | Review | Done
    #     owner:       any name          priority: None | Low | Medium | High | Urgent
    #     due:         2026-07-20        labels:   comma, separated
    #     description: free text
    #     subtasks:    then indented "- [ ]" / "- [x]" lines
    # • "- [x]" (with no fields) sends a simple task straight to Done.
    # • A "## Column" heading sets the column for the simple tasks below it.
    """

    private func saveSampleFormat() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sample-tasks.md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? Self.sampleFormat.write(to: url, atomically: true, encoding: .utf8)
            Toast.show("Saved sample-tasks.md — edit it, then Import › From file", symbol: "doc.text")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let n = importTasks(from: text)
        Toast.show(n > 0 ? "Imported \(n) task\(n == 1 ? "" : "s") from file"
                         : "No tasks found in that file",
                   symbol: n > 0 ? "square.and.arrow.down" : "info.circle")
    }

    /// Turn a Markdown / text file into tasks. Supports two levels:
    /// • Simple — each `- ` / `- [ ]` line is a task; `- [x]` lands in Done; a `## Column`
    ///   heading sets the column for the items beneath it.
    /// • Detailed — under a task, indented `key: value` lines set fields (status, owner,
    ///   priority, due, labels, description) and a `subtasks:` block adds subtasks.
    private func importTasks(from text: String) -> Int {
        var drafts: [TaskDraft] = []
        var column: TaskStatus = .todo
        var current: TaskDraft?
        var inSubtasks = false

        func flush() { if let d = current { drafts.append(d) }; current = nil; inSubtasks = false }

        for raw in text.components(separatedBy: "\n") {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let indented = raw.first == " " || raw.first == "\t"
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Column heading (top-level).
            if !indented, line.hasPrefix("#") {
                flush()
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
                if let s = TaskStatus.allCases.first(where: { $0.title.lowercased() == heading }) { column = s }
                continue
            }

            // Indented field / subtask belonging to the current task.
            if indented, current != nil {
                if line.lowercased().hasPrefix("subtasks") { inSubtasks = true; continue }
                if inSubtasks, line.hasPrefix("-") || line.hasPrefix("*") {
                    var t = line.dropFirst()
                    var sdone = false
                    let l = t.trimmingCharacters(in: .whitespaces).lowercased()
                    if l.hasPrefix("[x]") { sdone = true; t = t.trimmingCharacters(in: .whitespaces).dropFirst(3) }
                    else if l.hasPrefix("[ ]") { t = t.trimmingCharacters(in: .whitespaces).dropFirst(3) }
                    let title = t.trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { current?.subtasks.append((title, sdone)) }
                    continue
                }
                if let colon = line.firstIndex(of: ":") {
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "status": if let s = matchStatus(val) { current?.status = s }
                    case "owner", "assignee": current?.owner = val
                    case "priority": current?.priority = matchPriority(val)
                    case "due", "due date", "deadline": current?.due = parseDate(val)
                    case "labels", "tags": current?.labels = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    case "description", "desc", "details": current?.details = val
                    default: break
                    }
                    inSubtasks = false
                }
                continue
            }

            // Top-level task line.
            flush()
            var t = line
            var done = false
            let low = t.lowercased()
            if low.hasPrefix("- [x]") || low.hasPrefix("* [x]") { done = true; t = String(t.dropFirst(5)) }
            else if t.hasPrefix("- [ ]") || t.hasPrefix("* [ ]") { t = String(t.dropFirst(5)) }
            else if t.hasPrefix("- ") || t.hasPrefix("* ") { t = String(t.dropFirst(2)) }
            else if let r = t.range(of: #"^\d+\.\s"#, options: .regularExpression) { t.removeSubrange(r) }
            t = t.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)

            var owner: String?
            if let colon = t.firstIndex(of: ":"), t.distance(from: t.startIndex, to: colon) <= 20 {
                let head = String(t[..<colon]).trimmingCharacters(in: .whitespaces)
                if head.split(separator: " ").count <= 2, !head.isEmpty {
                    owner = head; t = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            guard t.count >= 2 else { continue }
            current = TaskDraft(title: t, status: done ? .done : column, owner: owner)
        }
        flush()

        for d in drafts {
            let task = library.createTask(title: d.title, details: d.details, status: d.status,
                                          priority: d.priority, owner: d.owner,
                                          labels: d.labels.isEmpty ? nil : d.labels, due: d.due)
            for (st, sdone) in d.subtasks {
                library.addSubtask(task.id, title: st)
                if sdone, let sub = library.task(task.id)?.subtaskList.last { library.toggleSubtask(task.id, subID: sub.id) }
            }
        }
        return drafts.count
    }

    private func matchStatus(_ v: String) -> TaskStatus? {
        TaskStatus.allCases.first { $0.title.lowercased() == v.lowercased() || $0.rawValue.lowercased() == v.lowercased() }
    }
    private func matchPriority(_ v: String) -> TaskPriority {
        TaskPriority.allCases.first { $0.title.lowercased() == v.lowercased() || $0.rawValue.lowercased() == v.lowercased() } ?? .none
    }
    private func parseDate(_ v: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd", "yyyy/MM/dd", "dd MMM yyyy", "MMM d, yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: v) { return d }
        }
        return nil
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
                md += "- [\(box)] \(t.key.map { "\($0): " } ?? "")\(t.title)\(owner)\n"
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

/// A task being assembled while parsing an import file.
private struct TaskDraft {
    var title: String
    var details = ""
    var status: TaskStatus
    var priority: TaskPriority = .none
    var owner: String?
    var labels: [String] = []
    var due: Date?
    var subtasks: [(String, Bool)] = []
    init(title: String, status: TaskStatus, owner: String? = nil) {
        self.title = title; self.status = status; self.owner = owner
    }
}
