import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var notionPageId: String
    var title: String
    var statusRaw: String = TaskStatus.notStarted.rawValue
    var dueDate: Date?
    var priorityRaw: String?
    var tags: [String] = []
    var recurrenceRaw: String = Recurrence.none.rawValue
    var lastEditedTime: Date?
    var lastSyncedAt: Date?
    var isDirty: Bool = false
    var isDeleted: Bool = false

    var project: ProjectItem?

    @Relationship(deleteRule: .cascade, inverse: \ReminderItem.task)
    var reminders: [ReminderItem] = []

    // MARK: - Computed Properties

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var priority: TaskPriority? {
        get { priorityRaw.flatMap { TaskPriority(rawValue: $0) } }
        set { priorityRaw = newValue?.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let dueDate, status != .done else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    // MARK: - Init

    init(notionPageId: String, title: String) {
        self.notionPageId = notionPageId
        self.title = title
    }

    // MARK: - Actions

    /// Complete this task. If recurring, advances due date and resets status.
    /// Returns true if the task was recycled (recurring), false if just marked done.
    @discardableResult
    func complete() -> Bool {
        if recurrence != .none, let dueDate {
            if let nextDate = recurrence.nextDueDate(from: dueDate) {
                self.dueDate = nextDate
                self.status = .notStarted
                self.isDirty = true
                return true
            }
        }
        self.status = .done
        self.isDirty = true
        return false
    }
}
