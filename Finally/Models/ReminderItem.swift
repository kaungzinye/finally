import Foundation
import SwiftData

@Model
final class ReminderItem {
    var id: UUID = UUID()
    var intervalSeconds: Int
    var label: String
    var notificationId: String
    var isScheduled: Bool = false
    var absoluteDate: Date?

    var task: TaskItem?

    /// Computed fire date — uses absoluteDate if set, otherwise offset from task's due date
    var fireDate: Date? {
        if let absoluteDate { return absoluteDate }
        guard let dueDate = task?.dueDate else { return nil }
        return dueDate.addingTimeInterval(-TimeInterval(intervalSeconds))
    }

    /// Interval-based reminder
    init(intervalSeconds: Int, label: String, taskNotionPageId: String) {
        self.intervalSeconds = intervalSeconds
        self.label = label
        self.notificationId = "task-\(taskNotionPageId)-reminder-\(intervalSeconds)"
    }

    /// Absolute date reminder
    init(absoluteDate: Date, label: String, taskNotionPageId: String) {
        self.intervalSeconds = 0
        self.absoluteDate = absoluteDate
        self.label = label
        self.notificationId = "task-\(taskNotionPageId)-reminder-abs-\(Int(absoluteDate.timeIntervalSince1970))"
    }
}
