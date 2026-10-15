import Foundation

extension TaskItem: TodayTask {
    var isOpen: Bool { status != .done && !isDeleted }
    var priorityRank: Int { priority?.sortOrder ?? TaskPriority.allCases.count }
    var hasOpenSubtasks: Bool { nextActionableSubtask != nil }
}

extension DailyFocus {
    /// The rest of Today below the focus. It leaves out every pick and the step standing in for a
    /// picked parent, so Other tasks never repeat a pick.
    func otherTasks(among tasks: [TaskItem], at referenceDate: Date, calendar: Calendar = .current) -> [Today.Member<TaskItem>] {
        let shown = Set(picks).union(executionPicks(among: tasks).compactMap { $0.task?.dailyFocusPick })
        return Today.members(of: tasks, at: referenceDate, calendar: calendar) { shown.contains($0.dailyFocusPick) }
    }
}
