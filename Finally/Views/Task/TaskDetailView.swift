import SwiftUI
import SwiftData

/// The sheet that opens from any task row. Every edit applies to the task as the user makes
/// it, and closing the sheet submits the dirty edit to its provider.
struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var showDatePicker = false
    @State private var showScheduledDayPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var showRemindMeAt = false
    @State private var newSubtaskTitle = ""

    /// The deadline picker's time toggle. The deadline changes when the picker commits a date.
    @State private var deadlinePickerHasTime = false
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
                    TextField("Task name", text: edit(\.title), axis: .vertical)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 4)
                        .accessibilityIdentifier("task-detail-title")

                    FlowLayout(spacing: 8) {
                        StatusChip(task: task)
                        fieldChips
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .paperRow()
                .listRowSeparator(.hidden)

                ReminderSection(task: task) { showRemindMeAt = true }
                    .cardRow()

                // Subtasks (only for non-subtask tasks)
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
                            TextField("Add subtask", text: $newSubtaskTitle)
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
        }
        .presentationBackground(Palette.sheet)
        .onDisappear(perform: submitPendingEdits)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(deadline: deadlineBinding, hasTime: $deadlinePickerHasTime)
        }
        .sheet(isPresented: $showScheduledDayPicker) {
            DatePickerSheet(scheduledDay: scheduledDayBinding)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: edit(\.priority))
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: edit(\.tags))
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: edit(\.project))
        }
        .sheet(isPresented: $showRemindMeAt) {
            RemindMeAtSheet { date in
                ReminderSection.save(task, store: modelContext, provider: taskProvider, asksPermission: true) {
                    task.taskReminders.append(.exact(ExactReminder(at: date)))
                }
            }
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(
                selection: edit(\.recurrence),
                customRule: edit(\.customRecurrenceRule),
                contextDate: task.deadline
            )
        }
    }

    @ViewBuilder
    private var fieldChips: some View {
        ChipView(
            label: task.scheduledDay.map { "Scheduled \(formattedPlanningDate($0, hasTime: false))" } ?? "Scheduled",
            icon: "scope",
            isPlaceholder: task.scheduledDay == nil
        ) { showScheduledDayPicker = true }
        .accessibilityIdentifier("task-detail-scheduled")

        ChipView(
            label: task.deadline.map { "Deadline \(formattedPlanningDate($0, hasTime: task.deadlineHasTime))" } ?? "Deadline",
            icon: "calendar",
            color: task.isOverdue ? Palette.urgent : Palette.ink,
            isPlaceholder: task.deadline == nil
        ) {
            deadlinePickerHasTime = task.deadlineHasTime
            showDatePicker = true
        }
        .accessibilityIdentifier("task-detail-deadline")

        ChipView(
            label: task.priority?.rawValue ?? "Priority",
            icon: "flag",
            color: task.priority?.color ?? Palette.ink,
            isPlaceholder: task.priority == nil
        ) { showPriorityPicker = true }

        ChipView(label: task.project?.title ?? "Inbox", icon: "folder") { showProjectPicker = true }

        ChipView(
            label: task.tags.isEmpty ? "Tags" : task.tags.joined(separator: ", "),
            icon: "tag",
            isPlaceholder: task.tags.isEmpty
        ) { showTagPicker = true }

        ChipView(
            label: task.recurrence == .custom
                ? (task.customRecurrenceRule?.summary ?? "Custom")
                : (task.recurrence == .none ? "Repeat" : task.recurrence.rawValue),
            icon: "repeat",
            isPlaceholder: task.recurrence == .none
        ) { showRecurrencePicker = true }
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
            NotificationService.shared.cancelRemindersForTask(subtask, modelContext: modelContext)
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

    // MARK: - Autosave

    /// A binding that writes straight to the task as a task detail edit.
    private func edit<Value>(_ field: ReferenceWritableKeyPath<TaskItem, Value>) -> Binding<Value> {
        Binding(
            get: { task[keyPath: field] },
            set: { value in task.edit { $0[keyPath: field] = value } }
        )
    }

    private var scheduledDayBinding: Binding<Date?> {
        Binding(
            get: { task.scheduledDay },
            set: { day in
                task.edit { $0.scheduledDay = day }
                planningDatesChanged()
            }
        )
    }

    private var deadlineBinding: Binding<Date?> {
        Binding(
            get: { task.deadline },
            set: { deadline in
                task.edit { $0.setDeadline(deadline, hasTime: deadlinePickerHasTime, defaults: .current()) }
                planningDatesChanged()
            }
        )
    }

    /// Reminders follow the deadline, and subtask dates spread across the scheduled window.
    private func planningDatesChanged() {
        if task.hasSubtasks {
            SubtaskScheduler.distributeSubtaskDates(parent: task)
        }
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }

    /// Closing the sheet submits the task's dirty edit. A failed submit leaves the edit dirty
    /// for the next sync.
    private func submitPendingEdits() {
        guard task.isDirty else { return }
        let task = task
        let store = modelContext
        let provider = taskProvider
        Task { await provider.submitPendingChangesReportingFailure(for: [task], store: store) }
    }

    private func formattedPlanningDate(_ date: Date, hasTime: Bool) -> String {
        date.formatted(
            date: .abbreviated,
            time: hasTime ? .shortened : .omitted
        )
    }
}
