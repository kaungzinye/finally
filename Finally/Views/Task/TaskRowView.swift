import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext

    @State private var showDatePicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var showReminderPicker = false

    private var formattedDueDate: String {
        guard let dueDate = task.dueDate else { return "—" }

        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(dueDate) {
            return "Yesterday"
        } else {
            let daysFromNow = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: dueDate).day ?? 0
            if daysFromNow > 0 && daysFromNow <= 6 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: dueDate)
            } else {
                return dueDate.formatted(.dateTime.month(.abbreviated).day())
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Line 1: Checkbox + (optional breadcrumb) + Title
            HStack(spacing: 8) {
                // Checkbox — left side
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()

                    withAnimation(.snappy) {
                        let recycled = task.complete()
                        if recycled {
                            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                        } else {
                            NotificationService.shared.cancelRemindersForTask(task)
                        }
                    }
                } label: {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.status == .done ? .green : .secondary)
                }
                .buttonStyle(.plain)

                // Title
                Text(task.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)
                    .opacity(task.status == .done ? 0.6 : 1.0)

                Spacer(minLength: 0)

                // Inline breadcrumb for sub-tasks
                if task.isSubtask, let parentTitle = task.parent?.title {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.turn.down.right")
                        Text(parentTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 80, alignment: .trailing)
                }
            }

            // Line 2: Properties bar + project on the right
            HStack(spacing: 6) {
                // Due date — orange when in active window, red when overdue
                Button { showDatePicker = true } label: {
                    Text(formattedDueDate)
                        .foregroundStyle(task.isOverdue ? .red : (task.isInActiveWindow ? .orange : .secondary))
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)

                // Priority
                Button { showPriorityPicker = true } label: {
                    Group {
                        if let priority = task.priority {
                            Image(systemName: priority.icon)
                                .foregroundStyle(priority.color)
                        } else {
                            Image(systemName: "flag")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)

                // Reminders
                Button { showReminderPicker = true } label: {
                    if !task.reminders.isEmpty {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "bell")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)

                // Tags — only show if not empty, with Notion colors
                if !task.tags.isEmpty {
                    Button { showTagPicker = true } label: {
                        HStack(spacing: 4) {
                            ForEach(Array(task.tags.prefix(2).enumerated()), id: \.offset) { index, tag in
                                let colorName = index < task.tagColors.count ? task.tagColors[index] : "default"
                                let tagColor = NotionColor.swiftUIColor(for: colorName)
                                Text(tag)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(tagColor.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(tagColor)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                }

                // Subtask progress
                if task.hasSubtasks {
                    let progress = task.subtaskProgress
                    HStack(spacing: 2) {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                        Text("\(progress.done)/\(progress.total)")
                            .font(.caption2)
                    }
                    .foregroundStyle(progress.done == progress.total ? .green : .secondary)
                }

                Spacer(minLength: 0)

                // Project — right aligned within properties row
                Button { showProjectPicker = true } label: {
                    HStack(spacing: 3) {
                        if let emoji = task.project?.iconEmoji {
                            Text(emoji)
                                .font(.caption)
                        }
                        Text(task.project?.title ?? "Inbox")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: 80, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation {
                    let recycled = task.complete()
                    if recycled {
                        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                    } else {
                        NotificationService.shared.cancelRemindersForTask(task)
                    }
                }
            } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button {
                showDatePicker = true
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            .tint(.orange)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: dueDateBinding)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: priorityBinding)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: tagsBinding)
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: projectBinding)
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(
                selection: recurrenceBinding,
                customRule: customRecurrenceBinding,
                contextDate: task.dueDate
            )
        }
        .sheet(isPresented: $showReminderPicker) {
            ReminderListView(task: task)
        }
    }

    // MARK: - Bindings that mark task dirty on change

    private var dueDateBinding: Binding<Date?> {
        Binding(
            get: { task.dueDate },
            set: { task.dueDate = $0; task.isDirty = true }
        )
    }

    private var priorityBinding: Binding<TaskPriority?> {
        Binding(
            get: { task.priority },
            set: { task.priority = $0; task.isDirty = true }
        )
    }

    private var tagsBinding: Binding<[String]> {
        Binding(
            get: { task.tags },
            set: { task.tags = $0; task.isDirty = true }
        )
    }

    private var projectBinding: Binding<ProjectItem?> {
        Binding(
            get: { task.project },
            set: { task.project = $0; task.isDirty = true }
        )
    }

    private var recurrenceBinding: Binding<Recurrence> {
        Binding(
            get: { task.recurrence },
            set: { task.recurrence = $0; task.isDirty = true }
        )
    }

    private var customRecurrenceBinding: Binding<RecurrenceRule?> {
        Binding(
            get: { task.customRecurrenceRule },
            set: { task.customRecurrenceRule = $0; task.isDirty = true }
        )
    }
}
