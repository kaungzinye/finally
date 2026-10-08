import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var showDatePicker = false
    @State private var showPlannedDayPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var newSubtaskTitle = ""
    @State private var subtaskReminderTarget: TaskItem? = nil

    @State private var editedTitle: String = ""
    @State private var editedDeadline: Date?
    @State private var editedPlannedDay: Date?
    @State private var editedDeadlineHasTime = false
    @State private var editedPlannedDayHasTime = false
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
                        Callout(message: syncErrorMessage) {
                            self.syncErrorMessage = nil
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }

                Group {
                    TextField("Task name", text: $editedTitle, axis: .vertical)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 4)

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
                    .pickerStyle(.segmented)

                    FlowLayout(spacing: 8) {
                        fieldChips
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .paperRow()
                .listRowSeparator(.hidden)

                // Reminders (inline)
                ReminderSectionContent(task: task)
                    .cardRow()

                Section {
                    HStack {
                        Label("Estimate", systemImage: "timer")
                        Spacer()
                        TextField("Minutes", text: $editedEstimate)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    .cardRow()
                }

                Section {
                    TextField(
                        "One URL per line",
                        text: $editedExternalReferences,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .cardRow()
                } header: {
                    SectionLabel("External references")
                }

                // Sub-tasks (only for non-subtask tasks)
                if !task.isSubtask {
                    Group {
                    Section {
                        // Progress
                        if task.hasSubtasks {
                            let progress = task.subtaskProgress
                            HStack {
                                ProgressView(value: Double(progress.done), total: Double(progress.total))
                                    .tint(Palette.ink)
                                Text("\(progress.done)/\(progress.total)")
                                    .font(.meta)
                                    .foregroundStyle(Palette.muted)
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
                                    PriorityRing(color: subtask.priority?.color ?? Palette.low, isDone: subtask.status == .done)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subtask.title)
                                        .strikethrough(subtask.status == .done, color: Palette.hairline)
                                        .foregroundStyle(subtask.status == .done ? Palette.muted : Palette.ink)
                                    if let suggested = subtask.effectiveSuggestedDate {
                                        Text(suggested.formatted(date: .abbreviated, time: .omitted))
                                            .font(.meta)
                                            .foregroundStyle(suggested < Calendar.current.startOfDay(for: Date()) && subtask.status != .done ? Palette.urgent : Palette.muted)
                                    }
                                }

                                Spacer()

                                subtaskReminderIndicator(subtask)

                                Button {
                                    subtaskReminderTarget = subtask
                                } label: {
                                    Image(systemName: subtask.taskReminders.isEmpty ? "bell" : "bell.badge")
                                        .foregroundStyle(subtask.taskReminders.isEmpty ? Palette.muted : Palette.ink)
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
                            Image(systemName: "plus")
                                .foregroundStyle(Palette.muted)
                            TextField("Add sub-task...", text: $newSubtaskTitle)
                                .onSubmit {
                                    addSubtask()
                                }
                        }
                    } header: {
                        SectionLabel("Subtasks")
                    }
                    }
                    .cardRow()
                }
            }
            .paperList(background: Palette.sheet)
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
        .presentationBackground(Palette.sheet)
        .onAppear {
            editedTitle = task.title
            editedDeadline = task.deadline
            editedPlannedDay = task.plannedDay
            editedDeadlineHasTime = task.deadlineHasTime
            editedPlannedDayHasTime = task.plannedDayHasTime
            editedPriority = task.priority
            editedTags = task.tags
            editedProject = task.project
            editedRecurrence = task.recurrence
            editedCustomRule = task.customRecurrenceRule
            editedEstimate = task.estimateMinutes.map(String.init) ?? ""
            editedExternalReferences = task.externalReferences.joined(separator: "\n")
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $editedDeadline, hasTime: $editedDeadlineHasTime)
        }
        .sheet(isPresented: $showPlannedDayPicker) {
            DatePickerSheet(selectedDate: $editedPlannedDay, hasTime: $editedPlannedDayHasTime)
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
                contextDate: editedDeadline
            )
        }
        .sheet(item: $subtaskReminderTarget) { subtask in
            SubtaskReminderSheet(subtask: subtask)
        }
    }

    @ViewBuilder
    private var fieldChips: some View {
        ChipView(
            label: editedPlannedDay.map { formattedPlanningDate($0, hasTime: editedPlannedDayHasTime) } ?? "Planned day",
            icon: "scope",
            isPlaceholder: editedPlannedDay == nil
        ) { showPlannedDayPicker = true }

        ChipView(
            label: editedDeadline.map { "Due \(formattedPlanningDate($0, hasTime: editedDeadlineHasTime))" } ?? "Deadline",
            icon: "calendar",
            isPlaceholder: editedDeadline == nil
        ) { showDatePicker = true }

        ChipView(
            label: editedPriority?.rawValue ?? "Priority",
            icon: "flag",
            color: editedPriority?.color ?? Palette.ink,
            isPlaceholder: editedPriority == nil
        ) { showPriorityPicker = true }

        ChipView(label: editedProject?.title ?? "Inbox", icon: "folder") { showProjectPicker = true }

        ChipView(
            label: editedTags.isEmpty ? "Tags" : editedTags.joined(separator: ", "),
            icon: "tag",
            isPlaceholder: editedTags.isEmpty
        ) { showTagPicker = true }

        ChipView(
            label: editedRecurrence == .custom
                ? (editedCustomRule?.summary ?? "Custom")
                : (editedRecurrence == .none ? "Repeat" : editedRecurrence.rawValue),
            icon: "repeat",
            isPlaceholder: editedRecurrence == .none
        ) { showRecurrencePicker = true }
    }

    @ViewBuilder
    private func subtaskReminderIndicator(_ subtask: TaskItem) -> some View {
        let now = Date()
        let nextFire = subtask.taskReminders.compactMap { $0.fireDate(for: subtask) }.filter { $0 > now }.min()
        if let fire = nextFire {
            Label(fire.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                .font(.meta)
                .foregroundStyle(Palette.muted)
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
        let deadlineChanged = task.deadline != editedDeadline
        let plannedDayChanged = task.plannedDay != editedPlannedDay

        task.title = editedTitle
        task.deadline = editedDeadline
        task.plannedDay = editedPlannedDay
        task.deadlineHasTime = editedDeadline != nil && editedDeadlineHasTime
        task.plannedDayHasTime = editedPlannedDay != nil && editedPlannedDayHasTime
        task.validatePlannedDay()
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

        // Reschedule reminders if deadline changed
        if deadlineChanged || plannedDayChanged {
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
