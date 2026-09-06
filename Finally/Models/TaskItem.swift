import Foundation
import SwiftData

@Model
final class TaskItem {
    var externalTaskID: String
    var title: String
    var statusRaw: String = TaskStatus.notStarted.rawValue
    var dueDate: Date?
    var dueDateHasTime: Bool = false
    var targetDate: Date?
    var targetDateHasTime: Bool = false
    var priorityRaw: String?
    var tags: [String] = []
    var tagColors: [String] = []
    var recurrenceRaw: String = Recurrence.none.rawValue
    var customRecurrenceJSON: String?
    var remindersJSON: String?
    var estimateMinutes: Int?
    var externalReferences: [String] = []
    var lastEditedTime: Date?
    var lastSyncedAt: Date?
    var isDirty: Bool = false
    var isDeleted: Bool = false
    var providerWorkspaceId: String?

    var parentId: String?
    var suggestedDate: Date?
    var suggestedDateOverride: Date?
    var sortIndex: Int = 0

    var project: ProjectItem?
    var parent: TaskItem?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.parent)
    var subtasks: [TaskItem] = []

    // MARK: - Reminder storage

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

    /// Subtasks the user still owns. A subtask awaiting a provider delete push is marked
    /// `isDeleted` and drops out of every derived view until the provider confirms it.
    var activeSubtasks: [TaskItem] { subtasks.filter { !$0.isDeleted } }

    var hasSubtasks: Bool { !activeSubtasks.isEmpty }

    var nextActionableSubtask: TaskItem? {
        activeSubtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }
            .first
    }

    var subtaskProgress: (done: Int, total: Int) {
        let active = activeSubtasks
        let total = active.count
        let done = active.filter { $0.status == .done }.count
        return (done, total)
    }

    var allSubtasksComplete: Bool {
        let active = activeSubtasks
        return !active.isEmpty && active.allSatisfy { $0.status == .done }
    }

    var effectiveSuggestedDate: Date? {
        suggestedDateOverride ?? suggestedDate ?? computedSuggestedDate
    }

    var effectiveDate: Date? {
        isSubtask ? (effectiveSuggestedDate ?? dueDate) : dueDate
    }

    // MARK: - Init

    init(externalTaskID: String, title: String) {
        self.externalTaskID = externalTaskID
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
        let sorted = parent.activeSubtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }
        guard let index = sorted.firstIndex(where: { $0.externalTaskID == externalTaskID }) else { return nil }

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

enum DeadlineDemoFixture {
    static func makeTask(referenceDate: Date = Date(), calendar: Calendar = .current) -> TaskItem {
        let task = TaskItem(externalTaskID: "deadline-demo-parent", title: "Ship the project proposal")
        task.status = .inProgress
        task.priority = .urgent
        task.tags = ["Launch", "Client"]
        task.recurrence = .weekly
        task.targetDate = calendar.date(byAdding: .day, value: 9, to: referenceDate)
        task.dueDate = calendar.date(byAdding: .day, value: 20, to: referenceDate)
        task.taskReminders = [
            .anchored(AnchoredReminder(anchor: .target, value: 1, unit: .days)),
            .anchored(AnchoredReminder(anchor: .due, value: 2, unit: .hours)),
        ]

        let subtaskDefinitions: [(String, Int, TaskStatus)] = [
            ("Confirm scope and milestones", 0, .done),
            ("Draft the implementation plan", 1, .inProgress),
            ("Review and send proposal", 2, .notStarted),
        ]

        task.subtasks = subtaskDefinitions.map { title, index, status in
            let subtask = TaskItem(externalTaskID: "deadline-demo-subtask-\(index)", title: title)
            subtask.parentId = task.externalTaskID
            subtask.parent = task
            subtask.sortIndex = index
            subtask.status = status
            subtask.suggestedDateOverride = calendar.date(byAdding: .day, value: index * 3, to: referenceDate)
            return subtask
        }

        return task
    }
}
