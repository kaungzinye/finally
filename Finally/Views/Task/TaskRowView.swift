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

    var body: some View {
        HStack(spacing: 12) {
            // Task content
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(task.title)
                    .lineLimit(2)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)
                    .opacity(task.status == .done ? 0.6 : 1.0)

                // Properties bar
                HStack(spacing: 8) {
                    // Due date — fixed width
                    Button { showDatePicker = true } label: {
                        Group {
                            if let dueDate = task.dueDate {
                                Text(dueDate.formatted(.dateTime.month(.abbreviated).day()))
                                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                            } else {
                                Text("No date")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                        .frame(width: 52, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    // Priority — fixed width icon
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
                        .frame(width: 16)
                    }
                    .buttonStyle(.plain)

                    // Tags — fill middle
                    Button { showTagPicker = true } label: {
                        HStack(spacing: 4) {
                            if task.tags.isEmpty {
                                Text("No tags")
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(task.tags.prefix(3), id: \.self) { tag in
                                    Text(tag)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.quaternary)
                                        .clipShape(Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.caption2)
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    // Project
                    Button { showProjectPicker = true } label: {
                        Text(task.project?.title ?? "Inbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 60, alignment: .trailing)
                    }
                    .buttonStyle(.plain)

                    // Recurrence
                    if task.recurrence != .none {
                        Button { showRecurrencePicker = true } label: {
                            Image(systemName: "repeat")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Checkbox — right side
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
        }
        .padding(.vertical, 4)
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
            RecurrencePicker(selection: recurrenceBinding)
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
}
