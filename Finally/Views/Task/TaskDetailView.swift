import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var showDatePicker = false
    @State private var showTargetDatePicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var newSubtaskTitle = ""
    @State private var subtaskReminderTarget: TaskItem? = nil

    @State private var editedTitle: String = ""
    @State private var editedDueDate: Date?
    @State private var editedTargetDate: Date?
    @State private var editedDueDateHasTime = false
    @State private var editedTargetDateHasTime = false
    @State private var editedPriority: TaskPriority?
    @State private var editedTags: [String] = []
    @State private var editedProject: ProjectItem?
    @State private var editedRecurrence: Recurrence = .none
    @State private var editedCustomRule: RecurrenceRule?
    @State private var editedEstimate = ""
    @State private var editedExternalReferences = ""
    @State private var syncErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let syncErrorMessage {
                    Section {
                        SyncErrorBanner(message: syncErrorMessage) {
                            self.syncErrorMessage = nil
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }

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
                                Text(formattedPlanningDate(date, hasTime: editedDueDateHasTime))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Button {
                        showTargetDatePicker = true
                    } label: {
                        HStack {
                            Label("Target Date", systemImage: "scope")
                            Spacer()
                            if let date = editedTargetDate {
                                Text(formattedPlanningDate(date, hasTime: editedTargetDateHasTime))
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
                            if editedRecurrence == .custom, let rule = editedCustomRule {
                                Text(rule.summary)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(editedRecurrence.rawValue)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Label("Estimate", systemImage: "timer")
                        Spacer()
                        TextField("Minutes", text: $editedEstimate)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                }

                Section("External References") {
                    TextField(
                        "One URL per line",
                        text: $editedExternalReferences,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                        let sortedSubtasks = sortedActiveSubtasks
                        ForEach(sortedSubtasks, id: \.externalTaskID) { subtask in
                            HStack(spacing: 10) {
                                Button {
                                    withAnimation {
                                        subtask.status = subtask.status == .done ? .notStarted : .done
                                        if subtask.status == .done {
                                            SubtaskScheduler.autoLevel(parent: task, completedSubtask: subtask)
                                            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
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
                                    if let suggested = subtask.effectiveSuggestedDate {
                                        Text(suggested.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundStyle(suggested < Calendar.current.startOfDay(for: Date()) && subtask.status != .done ? .red : .secondary)
                                    }
                                }

                                Spacer()

                                subtaskReminderIndicator(subtask)

                                Button {
                                    subtaskReminderTarget = subtask
                                } label: {
                                    Image(systemName: subtask.taskReminders.isEmpty ? "bell" : "bell.badge")
                                        .foregroundStyle(subtask.taskReminders.isEmpty ? Color.secondary : Color.orange)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onDelete { indexSet in
                            deleteSubtasks(at: indexSet)
                        }
                        .onMove { from, to in
                            var sorted = sortedActiveSubtasks
                            sorted.move(fromOffsets: from, toOffset: to)
                            for (i, subtask) in sorted.enumerated() {
                                subtask.sortIndex = i
                            }
                            SubtaskScheduler.distributeSubtaskDates(parent: task)
                            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
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
                        Task {
                            await saveChanges()
                            if syncErrorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(syncErrorMessage != nil)
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
            editedTargetDate = task.targetDate
            editedDueDateHasTime = task.dueDateHasTime
            editedTargetDateHasTime = task.targetDateHasTime
            editedPriority = task.priority
            editedTags = task.tags
            editedProject = task.project
            editedRecurrence = task.recurrence
            editedCustomRule = task.customRecurrenceRule
            editedEstimate = task.estimateMinutes.map(String.init) ?? ""
            editedExternalReferences = task.externalReferences.joined(separator: "\n")
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $editedDueDate, hasTime: $editedDueDateHasTime)
        }
        .sheet(isPresented: $showTargetDatePicker) {
            DatePickerSheet(selectedDate: $editedTargetDate, hasTime: $editedTargetDateHasTime)
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
            RecurrencePicker(
                selection: $editedRecurrence,
                customRule: $editedCustomRule,
                contextDate: editedDueDate
            )
        }
        .sheet(item: $subtaskReminderTarget) { subtask in
            SubtaskReminderSheet(subtask: subtask)
        }
    }

    @ViewBuilder
    private func subtaskReminderIndicator(_ subtask: TaskItem) -> some View {
        let now = Date()
        let nextFire = subtask.taskReminders.compactMap { $0.fireDate(for: subtask) }.filter { $0 > now }.min()
        if let fire = nextFire {
            Label(fire.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                .font(.caption2)
                .foregroundStyle(Color.orange)
        }
    }

    private var sortedActiveSubtasks: [TaskItem] {
        task.activeSubtasks.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Subtasks are provider-owned tasks, so a swipe delete takes the same route as every other
    /// delete: mark the record and let the provider adapter retire it remotely.
    private func deleteSubtasks(at offsets: IndexSet) {
        let sorted = sortedActiveSubtasks
        let removed = offsets.map { sorted[$0] }
        for subtask in removed {
            subtask.isDeleted = true
            subtask.isDirty = true
            NotificationService.shared.cancelRemindersForTask(subtask)
        }
        SubtaskScheduler.distributeSubtaskDates(parent: task)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        Task {
            do {
                try await taskProvider.submitPendingChanges(for: removed, store: modelContext)
            } catch {
                syncErrorMessage = error.localizedDescription
            }
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtask = TaskItem(externalTaskID: UUID().uuidString, title: title)
        subtask.providerWorkspaceId = task.providerWorkspaceId
        subtask.parentId = task.externalTaskID
        subtask.parent = task
        subtask.isDirty = true
        subtask.sortIndex = task.activeSubtasks.count
        modelContext.insert(subtask)

        newSubtaskTitle = ""

        // Recalculate dates after adding
        SubtaskScheduler.distributeSubtaskDates(parent: task)
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }

    private func saveChanges() async {
        let dueDateChanged = task.dueDate != editedDueDate
        let targetDateChanged = task.targetDate != editedTargetDate

        task.title = editedTitle
        task.dueDate = editedDueDate
        task.targetDate = editedTargetDate
        task.dueDateHasTime = editedDueDate != nil && editedDueDateHasTime
        task.targetDateHasTime = editedTargetDate != nil && editedTargetDateHasTime
        task.validateTargetDate()
        task.priority = editedPriority
        task.tags = editedTags
        task.project = editedProject
        task.recurrence = editedRecurrence
        task.customRecurrenceRule = editedCustomRule
        task.estimateMinutes = Int(editedEstimate.trimmingCharacters(in: .whitespacesAndNewlines))
        task.externalReferences = editedExternalReferences
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        task.isDirty = true

        // Reschedule reminders if due date changed
        if dueDateChanged || targetDateChanged {
            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            // Redistribute subtask dates if parent deadline changed
            if task.hasSubtasks {
                SubtaskScheduler.distributeSubtaskDates(parent: task)
            }
        }

        do {
            try await taskProvider.submitPendingChanges(for: [task], store: modelContext)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private func formattedPlanningDate(_ date: Date, hasTime: Bool) -> String {
        date.formatted(
            date: .abbreviated,
            time: hasTime ? .shortened : .omitted
        )
    }
}
