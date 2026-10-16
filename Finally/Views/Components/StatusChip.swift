import SwiftUI
import SwiftData

/// The task's status as one paper chip. Each tap cycles Not started, In progress, Complete.
/// Task detail and Board cards share it. `onCycle` runs after the task changes, so a caller
/// that submits edits right away does so there.
struct StatusChip: View {
    @Bindable var task: TaskItem
    var onCycle: () -> Void = {}
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ChipView(label: task.status.rawValue, icon: icon) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) {
                let recycled = task.cycleStatus()
                if task.status == .done, !recycled {
                    NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
                } else {
                    NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                }
            }
            onCycle()
        }
        .accessibilityIdentifier("status-chip")
        .accessibilityHint("Cycles the status")
    }

    private var icon: String {
        switch task.status {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}
