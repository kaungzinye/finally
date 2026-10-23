import SwiftUI
import SwiftData

/// One task on one line: the date in a fixed leading column, the title, a short trailing slot,
/// and the priority ring on the right. Every row has the same 48-point height, and a row with no
/// date keeps the empty column so titles line up. Today's Other tasks draw the same row at 40
/// points, and a Daily Focus pick draws as a numbered slot.
struct TaskRowView: View {
    enum Layout {
        case standard
        /// The same one line at 40 points.
        case compact
        /// A numbered Daily Focus slot: the number, the title over its date and project, and the
        /// ring. `isNext` colors the number of the pick to start with. A finished pick collapses
        /// to one short struck-through line.
        case focus(number: Int, isNext: Bool)
    }

    /// A trailing swipe that changes the task's place in Daily Focus: Remove on a pick, Focus on
    /// a task in Other tasks.
    enum FocusAction {
        case remove(() -> Void)
        case pick(() -> Void)
    }

    @Bindable var task: TaskItem
    var isSelected = false
    var focusAction: FocusAction?
    var layout: Layout = .standard
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var showDatePicker = false
    /// Wide enough for the widest compact label at the default text size: "May '28" measures 48
    /// points in the footnote rounded face, and a time such as "12:00 AM" on the second line 50.
    @ScaledMetric(relativeTo: .footnote) private var dateColumnWidth: CGFloat = 50

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

    private var minHeight: CGFloat {
        switch layout {
        case .standard: 48
        case .compact: 40
        case .focus: isDone ? 40 : 64
        }
    }

    var body: some View {
        content
        .swipeableCardRow(fill: isSelected ? Palette.selection : Palette.card, minHeight: minHeight)
        .swipeActions(edge: .leading) {
            Button(action: toggleCompletion) {
                Label(isDone ? "Reopen" : "Complete", systemImage: isDone ? "arrow.uturn.backward" : "checkmark")
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

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .standard, .compact:
            HStack(spacing: 8) {
                dateColumn

                Text(task.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(isDone, color: Palette.hairline)
                    .foregroundStyle(isDone || isMissedScheduledDay ? Palette.muted : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailing

                ring(diameter: 22, height: minHeight)
            }
        case .focus(let number, let isNext):
            HStack(spacing: 14) {
                Text("\(number)")
                    .font(isDone ? .focusNumberDone : .focusNumber)
                    .monospacedDigit()
                    .foregroundStyle(isNext ? Palette.high : Palette.muted.opacity(isDone ? 0.5 : 0.8))
                    .frame(width: 26)
                    .accessibilityLabel("Pick \(number)")

                if isDone {
                    Text(task.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .strikethrough(true, color: Palette.muted)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ring(diameter: 20, height: minHeight, doneFill: Palette.done, doneMark: .white)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.focusTitle)
                            .foregroundStyle(isMissedScheduledDay ? Palette.muted : Palette.ink)
                            .lineLimit(2)
                        focusMeta
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ring(diameter: 24, height: 44)
                }
            }
        }
    }

    /// The row date in words and the project, under a focus pick's title.
    @ViewBuilder
    private var focusMeta: some View {
        let rowDate = rowDate
        let project = task.project?.title
        if rowDate != nil || project != nil {
            let date = rowDate.map { Text($0.sentence).foregroundStyle(color(for: $0)) } ?? Text("")
            let separator = rowDate != nil && project != nil ? Text(" · ") : Text("")
            (date + separator + Text(project ?? "").foregroundStyle(Palette.muted))
                .font(.meta)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
    }

    /// The priority ring. Tapping it completes an open task and reopens a finished one.
    private func ring(diameter: CGFloat, height: CGFloat, doneFill: Color = Palette.ink, doneMark: Color = Palette.onInk) -> some View {
        Button(action: toggleCompletion) {
            PriorityRing(
                color: task.priority?.color ?? Palette.low, isDone: isDone, diameter: diameter,
                doneFill: doneFill, doneMark: doneMark
            )
            .frame(width: 44, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, -11)
        .accessibilityLabel(isDone ? "Reopen" : "Complete")
    }

    private var dateColumn: some View {
        let rowDate = rowDate
        return VStack(alignment: .leading, spacing: 0) {
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

    private func toggleCompletion() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            if isDone {
                task.move(to: .notStarted)
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else if task.complete() {
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
