import Foundation

/// Board column, matching a Linear-style workflow.
public enum TaskStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case todo, inProgress, review, done

    public init(from decoder: Decoder) throws {   // tolerant of old/unknown values
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus(rawValue: raw) ?? .todo
    }

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .review: return "Review"
        case .done: return "Done"
        }
    }
    /// Hex accent used by the UI for the status dot/column.
    public var colorHex: String {
        switch self {
        case .todo: return "#8A8F98"
        case .inProgress: return "#5E6AD2"
        case .review: return "#D177E0"
        case .done: return "#3FB950"
        }
    }
}

/// Issue priority, like Linear's Urgent → No priority scale.
public enum TaskPriority: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, low, medium, high, urgent

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskPriority(rawValue: raw) ?? .none
    }

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "No priority"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
    public var symbol: String {
        switch self {
        case .none: return "minus"
        case .low: return "chevron.down"
        case .medium: return "equal"
        case .high: return "chevron.up"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
    public var colorHex: String {
        switch self {
        case .none: return "#8A8F98"
        case .low: return "#8A8F98"
        case .medium: return "#E2A03F"
        case .high: return "#EF8E3B"
        case .urgent: return "#E5484D"
        }
    }
    public var rank: Int {
        switch self { case .urgent: return 4; case .high: return 3; case .medium: return 2; case .low: return 1; case .none: return 0 }
    }
}

/// A checklist item inside a task.
public struct SubTask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var done: Bool
    public var details: String?
    public init(id: String = UUID().uuidString, title: String, done: Bool = false, details: String? = nil) {
        self.id = id; self.title = title; self.done = done; self.details = details
    }
}

/// A comment in a task's activity feed.
public struct TaskComment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var author: String
    public var text: String
    public var date: Date
    public init(id: String = UUID().uuidString, author: String, text: String, date: Date = Date()) {
        self.id = id; self.author = author; self.text = text; self.date = date
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

/// A board task / issue.
public struct TaskItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var key: String?                // e.g. "SNAP-12"
    public var title: String
    public var details: String
    public var status: TaskStatus
    public var priority: TaskPriority?
    public var owner: String?              // assignee
    public var labels: [String]?
    public var due: Date?
    public var imageFile: String?          // legacy single attachment
    public var attachments: [String]?
    public var subtasks: [SubTask]?
    public var comments: [TaskComment]?
    public var createdAt: Date
    public var updatedAt: Date?
    public var order: Double
    public var history: [TaskEvent]
    public var sourceMeetingID: String?

    public init(id: String = UUID().uuidString, key: String? = nil, title: String, details: String = "",
                status: TaskStatus = .todo, priority: TaskPriority? = nil, owner: String? = nil,
                labels: [String]? = nil, due: Date? = nil, imageFile: String? = nil,
                attachments: [String]? = nil, subtasks: [SubTask]? = nil, comments: [TaskComment]? = nil,
                createdAt: Date = Date(), updatedAt: Date? = nil, order: Double = 0,
                history: [TaskEvent] = [], sourceMeetingID: String? = nil) {
        self.id = id; self.key = key; self.title = title; self.details = details; self.status = status
        self.priority = priority; self.owner = owner; self.labels = labels; self.due = due
        self.imageFile = imageFile; self.attachments = attachments; self.subtasks = subtasks
        self.comments = comments; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.order = order; self.history = history; self.sourceMeetingID = sourceMeetingID
    }

    public var priorityValue: TaskPriority { priority ?? .none }
    public var labelList: [String] { labels ?? [] }
    public var subtaskList: [SubTask] { subtasks ?? [] }
    public var commentList: [TaskComment] { comments ?? [] }
    public var files: [String] { (imageFile.map { [$0] } ?? []) + (attachments ?? []) }
    public var subtasksDone: Int { subtaskList.filter { $0.done }.count }
    public var subtasksTotal: Int { subtaskList.count }

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
        updated.updatedAt = date
        return updated
    }
}
