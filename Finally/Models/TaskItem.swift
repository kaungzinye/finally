import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var notionPageId: String
    var title: String
    var statusRaw: String = TaskStatus.notStarted.rawValue
    var dueDate: Date?
    var dueDateHasTime: Bool = false
    var targetDate: Date?
    var targetDateHasTime: Bool = false
    /// Legacy field — migrated to `targetDate` on first launch after Phase 6B.
    var startDate: Date?
    var priorityRaw: String?
    var tags: [String] = []
    var tagColors: [String] = []
    var recurrenceRaw: String = Recurrence.none.rawValue
    var customRecurrenceJSON: String?
    var remindersJSON: String?
    var lastEditedTime: Date?
    var lastSyncedAt: Date?
    var isDirty: Bool = false
    var isDeleted: Bool = false
    var isLocalOnly: Bool = false

    var parentId: String?
    /// Legacy field — migrated to `suggestedDateOverride`.
    var suggestedDate: Date?
    var suggestedDateOverride: Date?
    var sortIndex: Int = 0

    var project: ProjectItem?
    var parent: TaskItem?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.parent)
    var subtasks: [TaskItem] = []

    // Legacy relationship — kept for one-time migration from ReminderItem rows.
    @Relationship(deleteRule: .cascade, inverse: \ReminderItem.task)
    var reminders: [ReminderItem] = []

    // MARK: - Reminder storage (Phase 6B)

    var taskReminders: [TaskReminder] {
        get { TaskReminderCodec.decode(from: remindersJSON) }
        set { remindersJSON = TaskReminderCodec.encode(newValue) }
    }

    var hasReminders: Bool { !taskReminders.isEmpty }

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

    var isInActiveWindow: Bool {
        guard let target = targetDate, let due = dueDate, status != .done else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        return today >= Calendar.current.startOfDay(for: target) && today <= Calendar.current.startOfDay(for: due)
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

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

    var effectiveSuggestedDate: Date? {
        suggestedDateOverride ?? suggestedDate ?? computedSuggestedDate
    }

    var effectiveDate: Date? {
        isSubtask ? (effectiveSuggestedDate ?? dueDate) : dueDate
    }

    var legacyStartDate: Date? { startDate }
    var legacySuggestedDate: Date? { suggestedDate }

    // MARK: - Init

    init(notionPageId: String, title: String) {
        self.notionPageId = notionPageId
        self.title = title
    }

    // MARK: - Anchor helpers

    func anchorDate(for anchor: ReminderAnchor) -> Date? {
        switch anchor {
        case .due: return dueDate
        case .target: return targetDate
        }
    }

    func hasTimeForAnchor(_ anchor: ReminderAnchor) -> Bool {
        switch anchor {
        case .due: return dueDateHasTime
        case .target: return targetDateHasTime
        }
    }

    func adjustedAnchorDate(_ anchorDate: Date, hasTime: Bool, defaultReminderMinutes: Int?) -> Date {
        if hasTime || isSubtask {
            return anchorDate
        }
        let storedMinutes = defaultReminderMinutes
            ?? UserDefaults.standard.integer(forKey: AppConstants.defaultReminderTimeMinutesKey)
        let preferredMinutes = storedMinutes > 0 ? storedMinutes : AppConstants.defaultReminderTimeMinutes
        let hour = preferredMinutes / 60
        let minute = preferredMinutes % 60
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: anchorDate)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? anchorDate
    }

    var computedSuggestedDate: Date? {
        guard isSubtask, let parent else { return nil }
        let sorted = parent.subtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }
        guard let index = sorted.firstIndex(where: { $0.notionPageId == notionPageId }) else { return nil }

        let planningDate = parent.targetDate ?? parent.dueDate
        guard let planningDate else { return nil }

        let start = max(Date(), Calendar.current.startOfDay(for: Date()))
        let end = planningDate
        guard end > start else { return start }

        let totalInterval = end.timeIntervalSince(start)
        let count = sorted.count
        let fraction = Double(index) / Double(max(count, 1))
        return start.addingTimeInterval(totalInterval * fraction)
    }

    func validateTargetDate() {
        guard let targetDate, let dueDate else { return }
        if targetDate >= dueDate {
            self.targetDate = Calendar.current.date(byAdding: .day, value: -1, to: dueDate)
        }
    }

    // MARK: - Actions

    @discardableResult
    func complete() -> Bool {
        if recurrence != .none, let dueDate {
            let previousDue = dueDate
            let previousTarget = targetDate

            let nextDate: Date?
            if recurrence == .custom, let rule = customRecurrenceRule {
                nextDate = rule.nextDueDate(from: dueDate)
            } else {
                nextDate = recurrence.nextDueDate(from: dueDate)
            }

            if let nextDate {
                self.dueDate = nextDate
                if let previousTarget {
                    let offset = previousDue.timeIntervalSince(previousTarget)
                    self.targetDate = nextDate.addingTimeInterval(-offset)
                    validateTargetDate()
                }
                self.status = .notStarted
                self.isDirty = true

                for subtask in subtasks {
                    subtask.status = .notStarted
                    subtask.isDirty = true
                }
                return true
            }
        }

        for subtask in subtasks where subtask.status != .done {
            subtask.status = .done
        }
        self.status = .done
        self.isDirty = true
        return false
    }
}

extension TaskItem {
    var displaySuggestedDate: Date? { effectiveSuggestedDate }
}
