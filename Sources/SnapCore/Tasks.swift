import Foundation

/// Where a task sits on the board.
public enum TaskStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case backlog, todo, inProgress, done
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

/// One entry in a task's activity log.
public struct TaskEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    public var text: String
    public init(id: String = UUID().uuidString, date: Date = Date(), text: String) {
        self.id = id; self.date = date; self.text = text
    }
}

/// A board task: manually created or imported from a meeting's action items.
public struct TaskItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var details: String
    public var status: TaskStatus
    public var owner: String?
    public var due: Date?
    public var imageFile: String?          // relative path within the library, if attached
    public var createdAt: Date
    public var order: Double               // sort key within a column (smaller = higher)
    public var history: [TaskEvent]
    public var sourceMeetingID: String?    // set when imported from a meeting recording

    public init(id: String = UUID().uuidString, title: String, details: String = "",
                status: TaskStatus = .todo, owner: String? = nil, due: Date? = nil,
                imageFile: String? = nil, createdAt: Date = Date(), order: Double = 0,
                history: [TaskEvent] = [], sourceMeetingID: String? = nil) {
        self.id = id; self.title = title; self.details = details; self.status = status
        self.owner = owner; self.due = due; self.imageFile = imageFile
        self.createdAt = createdAt; self.order = order; self.history = history
        self.sourceMeetingID = sourceMeetingID
    }

    public var isOverdue: Bool {
        guard let due, status != .done else { return false }
        return due < Date()
    }
}

public enum TaskBoard {
    /// Move a task to a new status, appending a history entry (no-op if unchanged).
    public static func move(_ task: TaskItem, to status: TaskStatus, at date: Date = Date()) -> TaskItem {
        guard task.status != status else { return task }
        var updated = task
        updated.history.append(TaskEvent(date: date, text: "\(task.status.title) → \(status.title)"))
        updated.status = status
        return updated
    }
}
