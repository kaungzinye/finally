import SwiftUI
import SwiftData

/// One task on one line: the priority ring, the title, and a short trailing slot.
/// Every row has the same height whether or not the task carries a deadline or subtasks.
struct TaskRowView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var showDatePicker = false

    private var isDone: Bool { task.status == .done }

    private var rowDate: TaskRowDate? { TaskRowDate(for: task, at: Date()) }

    /// A missed scheduled day carries no alarm, so its row reads in muted text.
    private var isMissedScheduledDay: Bool { Today.reason(for: task, at: Date()) == .missedScheduledDay }

    private func color(for date: TaskRowDate) -> Color {
        guard date.kind == .deadline else { return Palette.muted }
        if task.isOverdue { return Palette.urgent }
        if task.isInActiveWindow { return Palette.high }
        return Palette.muted
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: complete) {
                PriorityRing(color: task.priority?.color ?? Palette.low, isDone: isDone)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -11)
            .accessibilityLabel(isDone ? "Completed" : "Complete")

            Text(task.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(isDone, color: Palette.hairline)
                .foregroundStyle(isDone || isMissedScheduledDay ? Palette.muted : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .cardRow()
        .compactRowInsets()
        .swipeActions(edge: .leading) {
            Button(action: complete) {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(Palette.done)
        }
        .swipeActions(edge: .trailing) {
            Button {
                showDatePicker = true
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            .tint(Palette.highFill)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(scheduledDay: scheduledDayBinding, latest: task.deadline)
        }
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            if task.isSubtask, let parentTitle = task.parent?.title {
                Label(parentTitle, systemImage: "arrow.turn.down.right")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .trailing)
            }
            if task.hasSubtasks {
                let progress = task.subtaskProgress
                Label("\(progress.done)/\(progress.total)", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            }
            if let rowDate {
                Text(rowDate.text)
                    .foregroundStyle(color(for: rowDate))
            }
        }
        .font(.meta)
        .foregroundStyle(Palette.muted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func complete() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            let recycled = task.complete()
            if recycled {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
            }
        }
        submitTaskMutation()
    }

    // MARK: - Reschedule

    /// Reschedule moves the scheduled day and never the deadline.
    private var scheduledDayBinding: Binding<Date?> {
        Binding(
            get: { task.scheduledDay },
            set: { day in
                task.reschedule(to: day)
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                submitTaskMutation()
            }
        )
    }

    private func submitTaskMutation() {
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: modelContext)
        }
    }
}
