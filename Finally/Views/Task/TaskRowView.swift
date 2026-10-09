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

    private var deadlineLabel: String? {
        guard let deadline = task.deadline else { return nil }

        let calendar = Calendar.current
        let time = task.deadlineHasTime
            ? " \(deadline.formatted(date: .omitted, time: .shortened))"
            : ""
        if calendar.isDateInToday(deadline) {
            return "Today\(time)"
        } else if calendar.isDateInTomorrow(deadline) {
            return "Tomorrow\(time)"
        } else if calendar.isDateInYesterday(deadline) {
            return "Yesterday\(time)"
        }
        let daysFromNow = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: deadline).day ?? 0
        if daysFromNow > 0 && daysFromNow <= 6 {
            return deadline.formatted(.dateTime.weekday(.abbreviated)) + time
        }
        return deadline.formatted(.dateTime.month(.abbreviated).day()) + time
    }

    private var deadlineColor: Color {
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
                .foregroundStyle(isDone ? Palette.muted : Palette.ink)
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
            .tint(Palette.ink)
        }
        .swipeActions(edge: .trailing) {
            Button {
                showDatePicker = true
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            .tint(Palette.high)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: deadlineBinding, hasTime: deadlineHasTimeBinding)
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
            if let deadlineLabel {
                Text(deadlineLabel)
                    .foregroundStyle(deadlineColor)
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
                NotificationService.shared.cancelRemindersForTask(task)
            }
        }
        submitTaskMutation()
    }

    // MARK: - Bindings that mark task dirty on change

    private var deadlineBinding: Binding<Date?> {
        Binding(
            get: { task.deadline },
            set: { task.deadline = $0; task.isDirty = true; submitTaskMutation() }
        )
    }

    private var deadlineHasTimeBinding: Binding<Bool> {
        Binding(
            get: { task.deadlineHasTime },
            set: { task.deadlineHasTime = $0; task.isDirty = true; submitTaskMutation() }
        )
    }

    private func submitTaskMutation() {
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: [task], store: modelContext)
        }
    }
}
