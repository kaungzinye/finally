import Foundation
import SwiftData

@Model
final class ReminderItem {
    var id: UUID = UUID()
    var intervalSeconds: Int
    var label: String
    var notificationId: String
    var isScheduled: Bool = false

    var task: TaskItem?

    /// Computed fire date based on task's due date
    var fireDate: Date? {
        guard let dueDate = task?.dueDate else { return nil }
        return dueDate.addingTimeInterval(-TimeInterval(intervalSeconds))
    }

    init(intervalSeconds: Int, label: String, taskNotionPageId: String) {
        self.intervalSeconds = intervalSeconds
        self.label = label
        self.notificationId = "task-\(taskNotionPageId)-reminder-\(intervalSeconds)"
    }
}
