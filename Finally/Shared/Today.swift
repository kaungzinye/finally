import Foundation

/// The task facts Today reads. App tasks and widget snapshots both provide them.
protocol TodayTask {
    var title: String { get }
    var isOpen: Bool { get }
    var scheduledDay: Date? { get }
    var deadline: Date? { get }
    var deadlineHasTime: Bool { get }
    /// Urgent sorts first at zero. A task without a priority sorts last.
    var priorityRank: Int { get }
    var isSubtask: Bool { get }
    /// The locally computed day to work on a subtask.
    var effectiveSuggestedDate: Date? { get }
    var hasOpenSubtasks: Bool { get }
    /// When the task finished, or nil while it is open or when its finish time is unknown.
    var completedAt: Date? { get }
}

/// Everything on the user's plate for the current day. The Today tab, the widgets, and the lock
/// screen ring all read this one definition.
enum Today {
    /// Why a task belongs to Today, in display order.
    enum Reason: Int, Comparable {
        case overdue
        case dueToday
        case scheduledToday
        case missedScheduledDay

        static func < (lhs: Reason, rhs: Reason) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Member<Task: TodayTask> {
        let task: Task
        let reason: Reason

        /// The date that orders members within one reason: the deadline for overdue and due
        /// tasks, the scheduled day for missed ones.
        fileprivate var sortDate: Date {
            switch reason {
            case .overdue, .dueToday: task.deadline ?? .distantPast
            case .scheduledToday: .distantPast
            case .missedScheduledDay: task.scheduledDay ?? .distantPast
            }
        }
    }

    /// The start of the new day when the calendar day at `now` differs from the day Today shows,
    /// or nil while that day still holds.
    static func dayChange(from shown: Date, at now: Date, calendar: Calendar = .current) -> Date? {
        let current = calendar.startOfDay(for: now)
        return calendar.isDate(shown, inSameDayAs: current) ? nil : current
    }

    /// Today's members in display order: overdue, due today, scheduled today, then missed
    /// scheduled days. `isExcluded` leaves tasks out, such as the Daily Focus picks above Other tasks.
    static func members<Task: TodayTask>(
        of tasks: [Task],
        at referenceDate: Date,
        calendar: Calendar = .current,
        excluding isExcluded: (Task) -> Bool = { _ in false }
    ) -> [Member<Task>] {
        tasks.compactMap { task in
            guard !isExcluded(task) else { return nil }
            return reason(for: task, at: referenceDate, calendar: calendar).map { Member(task: task, reason: $0) }
        }
        .sorted { lhs, rhs in
            if lhs.reason != rhs.reason { return lhs.reason < rhs.reason }
            let lhsDate = lhs.sortDate, rhsDate = rhs.sortDate
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            if lhs.task.priorityRank != rhs.task.priorityRank { return lhs.task.priorityRank < rhs.task.priorityRank }
            return lhs.task.title.localizedStandardCompare(rhs.task.title) == .orderedAscending
        }
    }

    static func reason(for task: some TodayTask, at referenceDate: Date, calendar: Calendar = .current) -> Reason? {
        guard task.isOpen, !task.hasOpenSubtasks else { return nil }
        let today = calendar.startOfDay(for: referenceDate)
        if let deadline = task.deadline {
            if isOverdue(deadline: deadline, hasTime: task.deadlineHasTime, at: referenceDate, calendar: calendar) {
                return .overdue
            }
            if calendar.startOfDay(for: deadline) == today { return .dueToday }
        }
        if task.isSubtask, let suggested = task.effectiveSuggestedDate, calendar.startOfDay(for: suggested) <= today {
            return .scheduledToday
        }
        if let scheduledDay = task.scheduledDay {
            let day = calendar.startOfDay(for: scheduledDay)
            if day == today { return .scheduledToday }
            if day < today { return .missedScheduledDay }
        }
        return nil
    }

    /// Why a finished task counts as Today's finished work: it finished on the reference date's day
    /// and was a member of Today just before it finished. The lock screen ring fills its section.
    static func finishedReason(for task: some TodayTask, at referenceDate: Date, calendar: Calendar = .current) -> Reason? {
        guard !task.isOpen, let completedAt = task.completedAt,
              calendar.isDate(completedAt, inSameDayAs: referenceDate) else { return nil }
        return reason(for: Unfinished(task: task), at: completedAt, calendar: calendar)
    }

    /// A deadline has passed once its time passes, or once its day ends when it has no time.
    static func isOverdue(deadline: Date, hasTime: Bool, at referenceDate: Date, calendar: Calendar = .current) -> Bool {
        hasTime ? deadline < referenceDate : calendar.startOfDay(for: deadline) < calendar.startOfDay(for: referenceDate)
    }
}

/// A finished task as it stood just before it finished.
private struct Unfinished<Base: TodayTask>: TodayTask {
    let task: Base

    var title: String { task.title }
    var isOpen: Bool { true }
    var scheduledDay: Date? { task.scheduledDay }
    var deadline: Date? { task.deadline }
    var deadlineHasTime: Bool { task.deadlineHasTime }
    var priorityRank: Int { task.priorityRank }
    var isSubtask: Bool { task.isSubtask }
    var effectiveSuggestedDate: Date? { task.effectiveSuggestedDate }
    var hasOpenSubtasks: Bool { task.hasOpenSubtasks }
    var completedAt: Date? { nil }
}
