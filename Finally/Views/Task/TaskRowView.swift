import SwiftUI
import SwiftData

/// One task on one line: the date in a fixed leading column, the title, a short trailing slot,
/// and the priority ring on the right. Every row has the same 48-point height, and a row with no
/// date keeps the empty column so titles line up.
struct TaskRowView: View {
    /// A trailing swipe that changes the task's place in Daily Focus: Remove on a pick, Focus on
    /// a task in Other tasks.
    enum FocusAction {
        case remove(() -> Void)
        case pick(() -> Void)
    }

    @Bindable var task: TaskItem
    var isSelected = false
    var focusAction: FocusAction?
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var showDatePicker = false
    /// Wide enough for "Yesterday" or "from Dec 30". A year or time sits on a second line.
    @ScaledMetric(relativeTo: .footnote) private var dateColumnWidth: CGFloat = 76

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
            dateColumn

            Text(task.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(isDone, color: Palette.hairline)
                .foregroundStyle(isDone || isMissedScheduledDay ? Palette.muted : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing

            Button(action: complete) {
                PriorityRing(color: task.priority?.color ?? Palette.low, isDone: isDone)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -11)
            .accessibilityLabel(isDone ? "Completed" : "Complete")
        }
        .swipeableCardRow(fill: isSelected ? Palette.selection : Palette.card)
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
            switch focusAction {
            case .remove(let remove):
                Button(role: .destructive, action: remove) {
                    Label("Remove", systemImage: "minus.circle")
                }
            case .pick(let pick):
                Button(action: pick) {
                    Label("Focus", systemImage: "scope")
                }
                .tint(Palette.inkControl)
            case nil:
                EmptyView()
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(scheduledDay: scheduledDayBinding, task: task)
        }
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let rowDate {
                Text(rowDate.columnDay)
                    .font(.meta)
                if let detail = rowDate.columnDetail {
                    Text(detail)
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .foregroundStyle(rowDate.map(color(for:)) ?? Palette.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: dateColumnWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowDate?.text ?? "")
        .accessibilityHidden(rowDate == nil)
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

    /// Reschedule moves the scheduled day, and the deadline too when the user confirms a day after it.
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
