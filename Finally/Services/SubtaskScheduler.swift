import Foundation

struct SubtaskScheduler {

    /// Distribute suggested dates backward from parent's targetDate (preferred) or dueDate.
    static func distributeSubtaskDates(parent: TaskItem) {
        let sorted = parent.subtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }

        guard !sorted.isEmpty else { return }

        let planningDate = parent.targetDate ?? parent.dueDate
        guard let deadline = planningDate else {
            for subtask in parent.subtasks where subtask.suggestedDateOverride == nil {
                subtask.suggestedDate = nil
            }
            return
        }

        let start = max(Date(), Calendar.current.startOfDay(for: Date()))
        let end = deadline

        guard end > start else {
            for subtask in sorted where subtask.suggestedDateOverride == nil {
                subtask.suggestedDate = start
            }
            return
        }

        let totalInterval = end.timeIntervalSince(start)
        let count = sorted.count

        for (index, subtask) in sorted.enumerated() {
            guard subtask.suggestedDateOverride == nil else { continue }
            let fraction = Double(index) / Double(max(count, 1))
            subtask.suggestedDate = start.addingTimeInterval(totalInterval * fraction)
        }
    }

    static func autoLevel(parent: TaskItem, completedSubtask: TaskItem) {
        guard let suggestedDate = completedSubtask.effectiveSuggestedDate else { return }

        let now = Date()
        let slip = now.timeIntervalSince(suggestedDate)
        guard slip > 0 else { return }

        let deadline = parent.targetDate ?? parent.dueDate ?? Date.distantFuture

        let remaining = parent.subtasks
            .filter { $0.status != .done && $0.notionPageId != completedSubtask.notionPageId }
            .sorted { $0.sortIndex < $1.sortIndex }

        for subtask in remaining {
            guard subtask.suggestedDateOverride == nil,
                  let date = subtask.suggestedDate else { continue }
            let shifted = date.addingTimeInterval(slip)
            subtask.suggestedDate = min(shifted, deadline)
        }
    }
}
