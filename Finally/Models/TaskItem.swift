import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var notionPageId: String
    var title: String
    var statusRaw: String = TaskStatus.notStarted.rawValue
    var dueDate: Date?
    var startDate: Date?  // Read-only from Notion sync, powers orange "active window" indicator
    var priorityRaw: String?
    var tags: [String] = []
    var tagColors: [String] = [] // Notion color names matching tags by index
    var recurrenceRaw: String = Recurrence.none.rawValue
    var customRecurrenceJSON: String?  // JSON-encoded RecurrenceRule for .custom recurrence
    var lastEditedTime: Date?
    var lastSyncedAt: Date?
    var isDirty: Bool = false
    var isDeleted: Bool = false
    var isLocalOnly: Bool = false

    // Sub-task support
    var parentId: String?
    var suggestedDate: Date?
    var sortIndex: Int = 0

    var project: ProjectItem?
    var parent: TaskItem?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.parent)
    var subtasks: [TaskItem] = []

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

    var customRecurrenceRule: RecurrenceRule? {
        get { RecurrenceRule.from(customRecurrenceJSON) }
        set { customRecurrenceJSON = newValue?.jsonString }
    }

    var isOverdue: Bool {
        guard let dueDate, status != .done else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    /// True when today falls between startDate and dueDate (task is in its active work window)
    var isInActiveWindow: Bool {
        guard let start = startDate, let due = dueDate, status != .done else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        return today >= Calendar.current.startOfDay(for: start) && today <= Calendar.current.startOfDay(for: due)
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    // Sub-task computed properties

    var isSubtask: Bool { parentId != nil }

    var hasSubtasks: Bool { !subtasks.isEmpty }

    var nextActionableSubtask: TaskItem? {
        subtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }
            .first
    }

    var subtaskProgress: (done: Int, total: Int) {
        let total = subtasks.count
        let done = subtasks.filter { $0.status == .done }.count
        return (done, total)
    }

    var allSubtasksComplete: Bool {
        !subtasks.isEmpty && subtasks.allSatisfy { $0.status == .done }
    }

    /// Effective date for display — sub-tasks use suggestedDate, regular tasks use dueDate
    var effectiveDate: Date? {
        isSubtask ? (suggestedDate ?? dueDate) : dueDate
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
            let nextDate: Date?
            if recurrence == .custom, let rule = customRecurrenceRule {
                nextDate = rule.nextDueDate(from: dueDate)
            } else {
                nextDate = recurrence.nextDueDate(from: dueDate)
            }
            if let nextDate {
                self.dueDate = nextDate
                self.status = .notStarted
                self.isDirty = true
                // Clear subtasks for next cycle
                for subtask in subtasks {
                    subtask.status = .done
                }
                return true
            }
        }
        // Mark all incomplete subtasks done too
        for subtask in subtasks where subtask.status != .done {
            subtask.status = .done
        }
        self.status = .done
        self.isDirty = true
        return false
    }
}
