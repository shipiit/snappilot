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

    /// The import file format, as a ready-to-edit sample.
    private static let sampleFormat = """
    # Tasks

    ## To do
    - [ ] You: Prepare the demo
    - [ ] Priya: Review the pull request
    - Buy the domain name

    ## In progress
    - [ ] Sam: Build the landing page

    ## Review
    - [ ] QA the release build

    ## Done
    - [x] Ship v0.1.8

    # How this maps
    # • Each "- " or "- [ ]" line becomes a task.
    # • "- [x]" items go to the Done column.
    # • A "## Column name" heading (To do / In progress / Review / Done) sets the column.
    # • "Name: task" adds an owner. Plain lines work too.
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

    /// Turn a Markdown / text checklist into tasks. Each list item becomes a task; `- [x]`
    /// items land in Done; a heading that matches a column name (## In progress) sets the
    /// status for the items beneath it.
    private func importTasks(from text: String) -> Int {
        var status: TaskStatus = .todo
        var count = 0
        for raw in text.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
                if let s = TaskStatus.allCases.first(where: { $0.title.lowercased() == heading }) { status = s }
                continue
            }
            var done = false
            let low = line.lowercased()
            if low.hasPrefix("- [x]") || low.hasPrefix("* [x]") { done = true; line = String(line.dropFirst(5)) }
            else if line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]") { line = String(line.dropFirst(5)) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { line = String(line.dropFirst(2)) }
            else if let r = line.range(of: #"^\d+\.\s"#, options: .regularExpression) { line.removeSubrange(r) }

            line = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            // Optional "Owner: task" prefix.
            var owner: String? = nil
            if let colon = line.firstIndex(of: ":"), line.distance(from: line.startIndex, to: colon) <= 20 {
                let head = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                if head.split(separator: " ").count <= 2, !head.isEmpty {
                    owner = head; line = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            guard line.count >= 2 else { continue }
            library.createTask(title: line, status: done ? .done : status, owner: owner)
            count += 1
        }
        return count
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
