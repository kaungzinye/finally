import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService

    @State private var showDatePicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var newSubtaskTitle = ""

    @State private var editedTitle: String = ""
    @State private var editedDueDate: Date?
    @State private var editedPriority: TaskPriority?
    @State private var editedTags: [String] = []
    @State private var editedProject: ProjectItem?
    @State private var editedRecurrence: Recurrence = .none

    var body: some View {
        NavigationStack {
            List {
                // Title
                Section {
                    TextField("Task name", text: $editedTitle)
                        .font(.title3)
                }

                // Status
                Section("Status") {
                    Picker("Status", selection: Binding(
                        get: { task.status },
                        set: { newStatus in
                            task.status = newStatus
                            task.isDirty = true
                        }
                    )) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }

                // Properties
                Section {
                    // Due Date
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            Label("Due Date", systemImage: "calendar")
                            Spacer()
                            if let date = editedDueDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Priority
                    Button {
                        showPriorityPicker = true
                    } label: {
                        HStack {
                            Label("Priority", systemImage: "flag")
                            Spacer()
                            if let priority = editedPriority {
                                HStack(spacing: 4) {
                                    Image(systemName: priority.icon)
                                        .foregroundStyle(priority.color)
                                    Text(priority.rawValue)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Project
                    Button {
                        showProjectPicker = true
                    } label: {
                        HStack {
                            Label("Project", systemImage: "folder")
                            Spacer()
                            Text(editedProject?.title ?? "Inbox")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Tags
                    Button {
                        showTagPicker = true
                    } label: {
                        HStack {
                            Label("Tags", systemImage: "tag")
                            Spacer()
                            if editedTags.isEmpty {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(editedTags.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Recurrence
                    Button {
                        showRecurrencePicker = true
                    } label: {
                        HStack {
                            Label("Repeat", systemImage: "repeat")
                            Spacer()
                            Text(editedRecurrence.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Reminders (inline)
                ReminderSectionContent(task: task)

                // Sub-tasks (only for non-subtask tasks)
                if !task.isSubtask {
                    Section("Sub-tasks") {
                        // Progress
                        if task.hasSubtasks {
                            let progress = task.subtaskProgress
                            HStack {
                                ProgressView(value: Double(progress.done), total: Double(progress.total))
                                    .tint(progress.done == progress.total ? .green : .blue)
                                Text("\(progress.done)/\(progress.total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Subtask list
                        let sortedSubtasks = task.subtasks.sorted { $0.sortIndex < $1.sortIndex }
                        ForEach(sortedSubtasks, id: \.notionPageId) { subtask in
                            HStack(spacing: 10) {
                                Button {
                                    withAnimation {
                                        subtask.status = subtask.status == .done ? .notStarted : .done
                                        if subtask.status == .done {
                                            SubtaskScheduler.autoLevel(parent: task, completedSubtask: subtask)
                                        }
                                    }
                                } label: {
                                    Image(systemName: subtask.status == .done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtask.status == .done ? .green : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subtask.title)
                                        .strikethrough(subtask.status == .done)
                                        .foregroundStyle(subtask.status == .done ? .secondary : .primary)
                                    if let suggested = subtask.suggestedDate {
                                        Text(suggested.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundStyle(suggested < Calendar.current.startOfDay(for: Date()) && subtask.status != .done ? .red : .secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .onDelete { indexSet in
                            let sorted = task.subtasks.sorted { $0.sortIndex < $1.sortIndex }
                            for index in indexSet {
                                modelContext.delete(sorted[index])
                            }
                            SubtaskScheduler.distributeSubtaskDates(parent: task)
                        }
                        .onMove { from, to in
                            var sorted = task.subtasks.sorted { $0.sortIndex < $1.sortIndex }
                            sorted.move(fromOffsets: from, toOffset: to)
                            for (i, subtask) in sorted.enumerated() {
                                subtask.sortIndex = i
                            }
                            SubtaskScheduler.distributeSubtaskDates(parent: task)
                        }

                        // Add subtask
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                            TextField("Add sub-task...", text: $newSubtaskTitle)
                                .onSubmit {
                                    addSubtask()
                                }
                        }
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            editedTitle = task.title
            editedDueDate = task.dueDate
            editedPriority = task.priority
            editedTags = task.tags
            editedProject = task.project
            editedRecurrence = task.recurrence
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $editedDueDate)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: $editedPriority)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: $editedTags)
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: $editedProject)
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(selection: $editedRecurrence)
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtask = TaskItem(notionPageId: UUID().uuidString, title: title)
        subtask.parentId = task.notionPageId
        subtask.parent = task
        subtask.isLocalOnly = true
        subtask.sortIndex = task.subtasks.count
        modelContext.insert(subtask)

        newSubtaskTitle = ""

        // Recalculate dates after adding
        SubtaskScheduler.distributeSubtaskDates(parent: task)
    }

    private func saveChanges() {
        let dueDateChanged = task.dueDate != editedDueDate

        task.title = editedTitle
        task.dueDate = editedDueDate
        task.priority = editedPriority
        task.tags = editedTags
        task.project = editedProject
        task.recurrence = editedRecurrence
        task.isDirty = true

        // Reschedule reminders if due date changed
        if dueDateChanged {
            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            // Redistribute subtask dates if parent deadline changed
            if task.hasSubtasks {
                SubtaskScheduler.distributeSubtaskDates(parent: task)
            }
        }

        // Push in background
        let context = modelContext
        Task {
            if let session = try? context.fetch(FetchDescriptor<UserSession>()).first {
                try? await syncService.pushDirtyChanges(session: session, modelContext: context)
            }
        }
    }
}
