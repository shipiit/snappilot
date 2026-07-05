import EventKit
import Foundation

/// Adds meeting action items to Apple Reminders.
enum TaskExporter {
    static func addToReminders(_ titles: [String]) {
        Task {
            let store = EKEventStore()
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = (try? await store.requestFullAccessToReminders()) ?? false
            } else {
                granted = (try? await store.requestAccess(to: .reminder)) ?? false
            }
            guard granted else {
                await MainActor.run {
                    Toast.show("Allow Reminders access in System Settings › Privacy & Security", symbol: "hand.raised.fill")
                }
                return
            }
            guard let list = store.defaultCalendarForNewReminders() else {
                await MainActor.run { Toast.show("No Reminders list is available", symbol: "exclamationmark.triangle.fill") }
                return
            }
            var saved = 0
            for title in titles {
                let reminder = EKReminder(eventStore: store)
                reminder.title = title
                reminder.calendar = list
                if (try? store.save(reminder, commit: false)) != nil { saved += 1 }
            }
            try? store.commit()
            let count = saved
            await MainActor.run {
                Toast.show("Added \(count) task\(count == 1 ? "" : "s") to Reminders", symbol: "checklist")
            }
        }
    }
}
