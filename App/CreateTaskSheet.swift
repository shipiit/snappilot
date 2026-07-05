import SwiftUI
import AppKit
import SnapCore

func taskHex(_ hex: String) -> Color { Color(nsColor: nsColor(fromHex: hex)) }

/// Linear-style "Create new task" modal: title + rich description + subtasks + attachments on
/// the left, and status / assignee / priority / due / labels on the right.
struct CreateTaskSheet: View {
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var status: TaskStatus = .todo
    @State private var priority: TaskPriority = .none
    @State private var assignee = ""
    @State private var labels: [String] = []
    @State private var hasDue = false
    @State private var due = Date()
    @State private var subtasks: [String] = []
    @State private var newSubtask = ""
    @State private var files: [URL] = []
    @State private var createAnother = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Create new task", systemImage: "plus.square")
                    .font(.title3.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(20)
            Divider()

            HStack(alignment: .top, spacing: 0) {
                leftColumn.frame(maxWidth: .infinity)
                Divider()
                rightColumn.frame(width: 300)
            }

            Divider()
            HStack {
                Toggle("Create another", isOn: $createAnother)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { create() } label: { Label("Create task", systemImage: "return") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 900, height: 720)
        .background(Theme.appBG)
    }

    // MARK: Left

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                field("Title", required: true) {
                    TextField("Enter a clear, specific title", text: $title).textFieldStyle(.plain)
                        .font(.title3)
                        .padding(10)
                        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(title.isEmpty ? 0.5 : 0.2)))
                }
                field("Description") {
                    MarkdownEditor(text: $details, placeholder: "Add a detailed description…", minHeight: 150)
                }
                field("Subtasks") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(subtasks.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 8) {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                                Text(s)
                                Spacer()
                                Button { subtasks.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                    .buttonStyle(.borderless)
                            }
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                            TextField("Add a subtask", text: $newSubtask).textFieldStyle(.plain)
                                .onSubmit { addSubtask() }
                        }
                    }
                }
                field("Attachments") { dropZone }
            }
            .padding(20)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperclip").font(.title2).foregroundStyle(Color.accentColor)
            Text("Drag and drop files here or click to upload").font(.callout)
            Text("Supports images, docs, pdf, zip and more").font(.caption).foregroundStyle(.secondary)
            if !files.isEmpty {
                Text(files.map { $0.lastPathComponent }.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26)
        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(Theme.stroke))
        .onTapGesture { pickFiles() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in files.append(url) } }
                }
            }
            return true
        }
    }

    // MARK: Right

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                row("Status", "circle.dotted") {
                    Menu {
                        ForEach(TaskStatus.allCases) { s in Button(s.title) { status = s } }
                    } label: { statusLabel(status) }.menuStyle(.borderlessButton)
                }
                row("Assignee", "person") {
                    TextField("Unassigned", text: $assignee).textFieldStyle(.roundedBorder)
                }
                row("Priority", "flag") {
                    Menu {
                        ForEach(TaskPriority.allCases) { p in Button(p.title) { priority = p } }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: priority.symbol).foregroundStyle(taskHex(priority.colorHex))
                            Text(priority.title)
                        }
                    }.menuStyle(.borderlessButton)
                }
                row("Due date", "calendar") {
                    HStack {
                        Toggle("", isOn: $hasDue).labelsHidden()
                        if hasDue { DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                        else { Text("Select date").foregroundStyle(.secondary) }
                    }
                }
                row("Labels", "tag") {
                    HStack(spacing: 4) {
                        ForEach(labels, id: \.self) { l in
                            Text(l).font(.caption2).padding(.horizontal, 7).padding(.vertical, 2)
                                .background(taskHex("#5E6AD2").opacity(0.25), in: Capsule())
                                .onTapGesture { labels.removeAll { $0 == l } }
                        }
                        Button { if let t = promptLabel() { labels.append(t) } } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Tips", systemImage: "lightbulb.fill").font(.caption.bold()).foregroundStyle(.purple)
                    Text("Set a due date and Snappilot will send you a reminder notification.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
        }
    }

    private func statusLabel(_ s: TaskStatus) -> some View {
        HStack(spacing: 6) {
            Circle().fill(taskHex(s.colorHex)).frame(width: 8, height: 8)
            Text(s.title)
        }
    }

    // MARK: Helpers

    private func field<C: View>(_ title: String, required: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if required { Text("*").foregroundStyle(.red) }
            }
            content()
        }
    }

    private func row<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: icon).font(.callout).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        subtasks.append(t); newSubtask = ""
    }

    private func pickFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { files.append(contentsOf: panel.urls) }
    }

    private func promptLabel() -> String? {
        let alert = NSAlert(); alert.messageText = "Add label"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = f; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let t = f.stringValue.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private func create() {
        addSubtask()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let task = library.createTask(title: t, details: details, status: status, priority: priority,
                                      owner: assignee.isEmpty ? nil : assignee,
                                      labels: labels.isEmpty ? nil : labels, due: hasDue ? due : nil)
        for s in subtasks { library.addSubtask(task.id, title: s) }
        for url in files { library.addAttachment(to: task.id, from: url) }

        if createAnother {
            title = ""; details = ""; subtasks = []; files = []; labels = []
        } else {
            dismiss()
        }
    }
}
