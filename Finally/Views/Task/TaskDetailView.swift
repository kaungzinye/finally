import SwiftUI
import SwiftData

/// The sheet that opens from any task row. Every edit applies to the task as the user makes
/// it, and closing the sheet submits the dirty edit to its provider.
struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(DailyFocusService.self) private var dailyFocusService
    @Environment(\.dismiss) private var dismiss

    @State private var showDatePicker = false
    @State private var showScheduledDayPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var showRemindMeAt = false
    @State private var newSubtaskTitle = ""
    @State private var confirmsDelete = false

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

                    header
                        .padding(.top, 10)
                        .padding(.bottom, 12)
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
                                        subtask.toggleCompletion()
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
                                        Text(DayMonth.text(for: suggested, at: Date()))
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
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete task", systemImage: "trash", role: .destructive) {
                            confirmsDelete = true
                        }
                        .accessibilityIdentifier("task-detail-delete")
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("task-detail-more")
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete task", role: .destructive, action: deleteTask)
            } message: {
                Text("It leaves its provider and any Daily Focus that holds it.")
            }
        }
        .presentationBackground(Palette.sheet)
        .onDisappear(perform: submitPendingEdits)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(deadline: deadlineBinding, hasTime: $deadlinePickerHasTime)
        }
        .sheet(isPresented: $showScheduledDayPicker) {
            DatePickerSheet(scheduledDay: scheduledDayBinding, task: task)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: edit(\.priority))
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: edit(\.tags))
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: edit(\.project), task: task)
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

    /// Status, then When, Details and Repeat, each under its own eyebrow and set apart by space.
    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("Status", selection: statusBinding) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("task-detail-status")

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("When")
                HStack(spacing: 10) {
                    PlanningDateCard(
                        caption: "Scheduled",
                        noun: "scheduled day",
                        label: task.scheduledDay.map { PlanningDateLabel(date: $0, hasTime: false, at: Date()) }
                    ) { showScheduledDayPicker = true }
                    .accessibilityIdentifier("task-detail-scheduled")

                    PlanningDateCard(
                        caption: "Deadline",
                        noun: "deadline",
                        label: task.deadline.map { PlanningDateLabel(date: $0, hasTime: task.deadlineHasTime, at: Date()) },
                        isOverdue: task.isOverdue
                    ) {
                        deadlinePickerHasTime = task.deadlineHasTime
                        showDatePicker = true
                    }
                    .accessibilityIdentifier("task-detail-deadline")
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Details")
                FlowLayout(spacing: 8) {
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
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Repeat")
                ChipView(
                    label: task.recurrence == .custom
                        ? (task.customRecurrenceRule?.summary ?? "Custom")
                        : (task.recurrence == .none ? "Doesn't repeat" : task.recurrence.rawValue),
                    icon: "repeat",
                    isPlaceholder: task.recurrence == .none
                ) { showRecurrencePicker = true }
                .accessibilityIdentifier("task-detail-repeat")
            }
        }
    }

    /// The status control takes the same path as a Board drop: Complete finishes the task, or
    /// starts a recurring obligation's next cycle and lands back on Not started.
    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { status in
                guard status != task.status else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy) {
                    let recycled = task.move(to: status)
                    if task.status == .done, !recycled {
                        NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
                    } else {
                        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
                    }
                }
            }
        )
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

    /// Marks the task deleted, lets every Daily Focus drop its pick, and closes the sheet. Closing
    /// submits the deletion to the task's own provider workspace.
    private func deleteTask() {
        NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
        let store = modelContext
        do {
            let changed = try task.delete(in: store)
            try store.save()
            let sessions = try store.fetch(FetchDescriptor<UserSession>())
            let service = dailyFocusService
            for (workspaceID, focuses) in Dictionary(grouping: changed, by: \.storageWorkspaceID) {
                let workspace = sessions.first { $0.workspaceId == workspaceID }
                Task { try? await service.save(focuses, workspace: workspace, store: store) }
            }
        } catch {
            syncErrorMessage = error.localizedDescription
            return
        }
        NotificationService.shared.rescheduleAllReminders(modelContext: store)
        try? WidgetPublisher.publish(store: store)
        dismiss()
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
                task.reschedule(to: day)
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

    /// Closing the sheet submits the task's dirty edit and its dirty steps. A failed submit
    /// leaves the edits dirty for the next sync.
    private func submitPendingEdits() {
        let edits = task.pendingEdits
        guard !edits.isEmpty else { return }
        let store = modelContext
        let provider = taskProvider
        Task { await provider.submitPendingChangesReportingFailure(for: edits, store: store) }
    }
}

/// One of the two When cards: a small caption, the day in large rounded type, and what the day
/// leaves out below it. An overdue deadline draws in red, and an empty card offers "Add".
private struct PlanningDateCard: View {
    let caption: String
    /// What the card holds, for VoiceOver's hint, such as "scheduled day".
    let noun: String
    let label: PlanningDateLabel?
    var isOverdue = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 2)
                Text(label?.day ?? "Add")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(label == nil ? Palette.muted : (isOverdue ? Palette.urgent : Palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label?.detail ?? " ")
                    .font(.meta)
                    .foregroundStyle(isOverdue ? Palette.urgent : Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(label?.spoken ?? "none")")
        .accessibilityValue(isOverdue ? "Overdue" : "")
        .accessibilityHint(label == nil ? "Adds a \(noun)" : "Changes the \(noun)")
        .accessibilityAddTraits(.isButton)
    }
}
