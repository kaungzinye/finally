import Foundation

struct SubtaskScheduler {

    /// Evenly distribute suggestedDates across subtasks between now and the parent's dueDate.
    /// Subtasks are ordered by sortIndex. No deadline = no dates assigned.
    static func distributeSubtaskDates(parent: TaskItem) {
        let sorted = parent.subtasks
            .filter { $0.status != .done }
            .sorted { $0.sortIndex < $1.sortIndex }

        guard !sorted.isEmpty, let deadline = parent.dueDate else {
            // No deadline — clear suggested dates
            for subtask in parent.subtasks {
                subtask.suggestedDate = nil
            }
            return
        }

        let start = max(Date(), Calendar.current.startOfDay(for: Date()))
        let end = deadline

        guard end > start else {
            // Deadline already passed — assign all to today
            for subtask in sorted {
                subtask.suggestedDate = start
            }
            return
        }

        let totalInterval = end.timeIntervalSince(start)
        let count = sorted.count

        for (index, subtask) in sorted.enumerated() {
            let fraction = Double(index) / Double(max(count, 1))
            subtask.suggestedDate = start.addingTimeInterval(totalInterval * fraction)
        }
    }

    /// When a subtask is completed late, shift subsequent incomplete subtasks forward.
    /// Capped at the parent's deadline.
    static func autoLevel(parent: TaskItem, completedSubtask: TaskItem) {
        guard let suggestedDate = completedSubtask.suggestedDate else { return }

        let now = Date()
        let slip = now.timeIntervalSince(suggestedDate)
        guard slip > 0 else { return } // Completed on time or early — no adjustment needed

        let deadline = parent.dueDate ?? Date.distantFuture

        let remaining = parent.subtasks
            .filter { $0.status != .done && $0.notionPageId != completedSubtask.notionPageId }
            .sorted { $0.sortIndex < $1.sortIndex }

        for subtask in remaining {
            guard let date = subtask.suggestedDate else { continue }
            let shifted = date.addingTimeInterval(slip)
            subtask.suggestedDate = min(shifted, deadline)
        }
    }
}
