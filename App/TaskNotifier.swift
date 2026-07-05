import Foundation
import UserNotifications
import SnapCore

/// Schedules local notifications so the user is reminded when a task is due.
enum TaskNotifier {
    private static func id(_ taskID: String) -> String { "snappilot-task-\(taskID)" }

    /// Ask for notification permission once (call at launch).
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// (Re)schedule a task's reminder. Cancels any existing one first, and skips tasks that
    /// are done or have no future due date.
    static func schedule(_ task: TaskItem) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id(task.id)])
        guard let due = task.due, task.status != .done, due > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task due: \(task.title)"
        if let owner = task.owner, !owner.isEmpty { content.body = "Owner: \(owner)" }
        else { content.body = "Snappilot task reminder" }
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id(task.id), content: content, trigger: trigger))
    }

    static func cancel(_ taskID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(taskID)])
    }
}
