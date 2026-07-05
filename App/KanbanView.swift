import SwiftUI
import AppKit
import SnapCore

/// A Linear-style task board: columns per status, colored issue-key chips, priority,
/// subtask progress, assignee avatars, and drag-to-change-status.
struct KanbanView: View {
    @ObservedObject var library: LibraryStore
    @State private var creating = false
    @State private var dropTarget: TaskStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TaskStatus.allCases) { column($0) }
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
        }
        .background(Theme.appBG)
        .sheet(isPresented: $creating) { CreateTaskSheet(library: library) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Roadmap").font(.title2.bold())
                Text("Track and manage work across the board").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { let n = library.importMeetingActionItems()
                Toast.show(n > 0 ? "Imported \(n) task\(n == 1 ? "" : "s")" : "No new meeting tasks", symbol: "square.and.arrow.down")
            } label: { Label("Import", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
            Menu {
                Button("Copy checklist") { copyTasks() }
                Button("Export .md") { exportTasks() }
                Button("Add open tasks to Reminders") { remind() }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }.fixedSize()
            Button { creating = true } label: { Label("New task", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
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
            if !task.labelList.isEmpty {
                HStack(spacing: 4) {
                    ForEach(task.labelList.prefix(3), id: \.self) { l in
                        Text(l).font(.system(size: 9, weight: .medium)).foregroundStyle(taskHex("#5E6AD2"))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(taskHex("#5E6AD2").opacity(0.18), in: Capsule())
                    }
                }
            }
            HStack(spacing: 8) {
                if let key = task.key {
                    Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(taskHex(task.status.colorHex))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(taskHex(task.status.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                }
                if task.priorityValue != .none {
                    Image(systemName: task.priorityValue.symbol).font(.system(size: 10))
                        .foregroundStyle(taskHex(task.priorityValue.colorHex))
                }
                if task.subtasksTotal > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist").font(.system(size: 9))
                        Text("\(task.subtasksDone)/\(task.subtasksTotal)").font(.system(size: 10))
                    }.foregroundStyle(.secondary)
                }
                if task.isOverdue {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 10)).foregroundStyle(.red)
                }
                Spacer()
                if let owner = task.owner, !owner.isEmpty { avatar(owner) }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
    }

    private func avatar(_ name: String) -> some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        let palette = ["#5E6AD2", "#3FB950", "#E5484D", "#E2A03F", "#D177E0", "#0EA5E9"]
        let color = taskHex(palette[abs(name.hashValue) % palette.count])
        return Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 22, height: 22).background(color, in: Circle())
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
