import SwiftData
import SwiftUI

/// Completing, reopening, and rescheduling a task from a row, shared by the SwiftUI rows and
/// the UIKit Today list.
@MainActor
enum TaskCompletion {
    /// Completes an open task or reopens a finished one, with a light tap. The reminder and
    /// provider work waits until the row's animation ends, since fetching every task
    /// mid-animation drops frames.
    static func toggle(
        _ task: TaskItem,
        animation: Animation? = nil,
        modelContext: ModelContext,
        taskProvider: TaskProviderCoordinator
    ) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let wasDone = task.status == .done
        var completed = false
        withAnimation(animation) {
            if wasDone {
                task.move(to: .notStarted)
            } else {
                completed = task.complete()
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if wasDone || completed {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
            }
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: modelContext)
        }
    }

    /// Moves the scheduled day, and the deadline too when the user confirmed a day after it.
    static func reschedule(
        _ task: TaskItem,
        to day: Date?,
        modelContext: ModelContext,
        taskProvider: TaskProviderCoordinator
    ) {
        task.reschedule(to: day)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: modelContext)
        }
    }
}
