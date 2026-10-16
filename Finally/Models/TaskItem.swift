import Foundation
import SwiftData

@Model
final class TaskItem {
    var externalTaskID: String
    var title: String
    var statusRaw: String = TaskStatus.notStarted.rawValue
    var deadline: Date?
    var deadlineHasTime: Bool = false
    var scheduledDay: Date?
    var priorityRaw: String?
    var tags: [String] = []
    var tagColors: [String] = []
    var recurrenceRaw: String = Recurrence.none.rawValue
    var customRecurrenceJSON: String?
    var remindersJSON: String?
    var lastEditedTime: Date?
    var lastSyncedAt: Date?
    var serverRevision: Int64 = 0
    var serverSnapshotJSON: String?
    var serverTaskMissing: Bool = false
    var serverConflictJSON: String?
    var serverConflictFields: [String] = []
    var isDirty: Bool = false
    var isDeleted: Bool = false
    var providerWorkspaceId: String?

    var parentId: String?
    var suggestedDate: Date?
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

    var deadlineReminderOffsets: [DeadlineReminderOffset] {
        taskReminders.compactMap { reminder in
            if case .deadline(let rule) = reminder { rule.offset } else { nil }
        }
    }

    /// What the + chip offers: the short list minus the task's own chips. "1 hour before"
    /// needs a timed deadline.
    var addableDeadlineReminderOffsets: [DeadlineReminderOffset] {
        guard deadline != nil else { return [] }
        let present = deadlineReminderOffsets
        return DeadlineReminderOffset.menu.filter { offset in
            !present.contains(offset) && (deadlineHasTime || offset != .hourBefore)
        }
    }

    /// Sets the deadline from a local edit. A deadline going from empty to set receives the
    /// default deadline reminders, and clearing it drops its deadline reminders. A deadline
    /// gaining a time receives the default hour-before reminder. Moving a deadline keeps the
    /// task's own list.
    func setDeadline(_ newDeadline: Date?, hasTime: Bool, defaults: DefaultDeadlineReminders) {
        let hadDeadline = deadline != nil
        let hadTime = deadlineHasTime
        deadline = newDeadline
        deadlineHasTime = newDeadline != nil && hasTime
        if newDeadline == nil {
            taskReminders.removeAll { if case .deadline = $0 { true } else { false } }
        } else if !hadDeadline {
            defaults.offsets(deadlineHasTime: deadlineHasTime).forEach(addDeadlineReminder)
        } else if deadlineHasTime, !hadTime, defaults.offsets.contains(.hourBefore) {
            addDeadlineReminder(.hourBefore)
        }
    }

    /// Adds a deadline reminder. A task holds at most one rule per offset.
    func addDeadlineReminder(_ offset: DeadlineReminderOffset) {
        guard offset.isValid, !deadlineReminderOffsets.contains(offset) else { return }
        taskReminders.append(.deadline(DeadlineReminder(offset: offset)))
    }

    func removeReminder(id: UUID) {
        taskReminders.removeAll { $0.id == id }
    }

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
        guard let deadline, status != .done else { return false }
        return Today.isOverdue(deadline: deadline, hasTime: deadlineHasTime, at: Date())
    }

    var isInActiveWindow: Bool {
        guard let scheduledDay, let deadline, status != .done else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        return today >= Calendar.current.startOfDay(for: scheduledDay)
            && today <= Calendar.current.startOfDay(for: deadline)
    }

    var isDeadlineToday: Bool {
        guard let deadline else { return false }
        return Calendar.current.isDateInToday(deadline)
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
        suggestedDate ?? computedSuggestedDate
    }

    var effectiveDate: Date? {
        isSubtask ? (effectiveSuggestedDate ?? deadline) : deadline
    }

    // MARK: - Init

    init(externalTaskID: String, title: String) {
        self.externalTaskID = externalTaskID
        self.title = title
    }

    var computedSuggestedDate: Date? {
        guard isSubtask, let parent else { return nil }
        let sorted = parent.activeSubtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }
        guard let index = sorted.firstIndex(where: { $0.externalTaskID == externalTaskID }) else { return nil }

        let planningDate = parent.scheduledDay ?? parent.deadline
        guard let planningDate else { return nil }

        let start = max(Date(), Calendar.current.startOfDay(for: Date()))
        let end = planningDate
        guard end > start else { return start }

        let totalInterval = end.timeIntervalSince(start)
        let count = sorted.count
        let fraction = Double(index) / Double(max(count, 1))
        return start.addingTimeInterval(totalInterval * fraction)
    }

    /// A scheduled day may fall on its deadline's day. One that falls after it moves back to
    /// the deadline's day.
    func validateScheduledDay(calendar: Calendar = .current) {
        guard let scheduledDay, let deadline else { return }
        let deadlineDay = calendar.startOfDay(for: deadline)
        if calendar.startOfDay(for: scheduledDay) > deadlineDay {
            self.scheduledDay = deadlineDay
        }
    }

    // MARK: - Actions

    /// Applies one task detail edit to the task. The task becomes a dirty edit, and its
    /// scheduled day stays on or before its deadline's day.
    func edit(calendar: Calendar = .current, _ change: (TaskItem) -> Void) {
        change(self)
        validateScheduledDay(calendar: calendar)
        isDirty = true
    }

    /// One tap of the status chip: Not started, then In progress, then Complete, then Not
    /// started again. Reaching Complete takes the same path as the row ring, so a recurring
    /// obligation starts its next cycle. Returns true when it did.
    @discardableResult
    func cycleStatus() -> Bool {
        switch status {
        case .notStarted:
            status = .inProgress
        case .inProgress:
            return complete()
        case .done:
            status = .notStarted
        }
        isDirty = true
        return false
    }

    /// A card dropped on a Board column takes that column's status as a dirty edit.
    /// Dropping it on its own column changes nothing. Dropping it on Complete takes the same
    /// path as the row ring, so a recurring obligation starts its next cycle. Returns true when it did.
    @discardableResult
    func move(to status: TaskStatus) -> Bool {
        guard status != self.status else { return false }
        if status == .done { return complete() }
        self.status = status
        isDirty = true
        return false
    }

    @discardableResult
    func complete() -> Bool {
        if recurrence != .none, let deadline {
            let previousDeadline = deadline
            let previousScheduledDay = scheduledDay

            let nextDate: Date?
            if recurrence == .custom, let rule = customRecurrenceRule {
                nextDate = rule.nextDeadline(from: deadline)
            } else {
                nextDate = recurrence.nextDeadline(from: deadline)
            }

            if let nextDate {
                self.deadline = nextDate
                if let previousScheduledDay {
                    let offset = previousDeadline.timeIntervalSince(previousScheduledDay)
                    self.scheduledDay = nextDate.addingTimeInterval(-offset)
                    validateScheduledDay()
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
        task.scheduledDay = calendar.date(byAdding: .day, value: 9, to: referenceDate)
        task.setDeadline(calendar.date(byAdding: .day, value: 20, to: referenceDate), hasTime: false, defaults: .standard)

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
            subtask.suggestedDate = calendar.date(byAdding: .day, value: index * 3, to: referenceDate)
            return subtask
        }

        return task
    }
}
