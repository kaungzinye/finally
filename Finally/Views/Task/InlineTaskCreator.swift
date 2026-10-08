import SwiftUI
import SwiftData

struct InlineTaskCreator: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Query(sort: \ProjectItem.title) private var allProjects: [ProjectItem]
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var allTasks: [TaskItem]
    @Query private var sessions: [UserSession]

    @State private var taskTitle = ""
    @State private var deadline: Date?
    @State private var plannedDay: Date?
    @State private var deadlineHasTime = false
    @State private var priority: TaskPriority?
    @State private var tags: [String] = []
    @State private var project: ProjectItem?
    @State private var recurrence: Recurrence = .none
    @State private var customRecurrenceRule: RecurrenceRule?
    @State private var reminderChoices: [ReminderChoice] = []
    @State private var parentTask: TaskItem?

    // NLP auto-detection tracking
    @State private var nlpDetectedDate = false
    @State private var nlpDetectedPriority = false
    @State private var nlpDetectedProject = false
    @State private var nlpDetectedTags = false
    @State private var projectSuggestions: [ProjectItem] = []
    @State private var tagSuggestions: [String] = []
    @State private var showProjectSuggestions = false
    @State private var showTagSuggestions = false

    @State private var showDatePicker = false
    @State private var showPlannedDayPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var showReminderPicker = false
    @State private var showParentPicker = false

    @FocusState private var isFocused: Bool
    @State private var syncErrorMessage: String?

    var presetProject: ProjectItem?

    private var selectedProjects: [ProjectItem] {
        allProjects.scoped(to: sessions.selectedProviderWorkspace)
    }

    private var selectedTasks: [TaskItem] {
        allTasks.scoped(to: sessions.selectedProviderWorkspace)
    }

    var body: some View {
        VStack(spacing: 10) {
            if let syncErrorMessage {
                Callout(message: syncErrorMessage) {
                    self.syncErrorMessage = nil
                }
            }

            // Text field
            TextField("Add a task...", text: $taskTitle)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .onChange(of: taskTitle) { _, newValue in
                    handleNLPParsing(newValue)
                    updateSuggestions(newValue)
                }

            // Inline suggestions for @ and #
            if showProjectSuggestions && !projectSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(projectSuggestions.prefix(5), id: \.externalProjectID) { proj in
                            Button {
                                selectProjectSuggestion(proj)
                            } label: {
                                HStack(spacing: 4) {
                                    if let emoji = proj.iconEmoji {
                                        Text(emoji).font(.caption)
                                    }
                                    Text(proj.title)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if showTagSuggestions && !tagSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagSuggestions.prefix(5), id: \.self) { tag in
                            Button {
                                selectTagSuggestion(tag)
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Selected chips
            if hasSelections {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let deadline {
                            ChipView(
                                label: formatPlanningDate(deadline, hasTime: deadlineHasTime),
                                icon: "calendar"
                            ) { showDatePicker = true }
                        }
                        if let plannedDay {
                            ChipView(
                                label: "Planned \(formatPlanningDate(plannedDay, hasTime: false))",
                                icon: "scope"
                            ) { showPlannedDayPicker = true }
                        }
                        if let priority {
                            ChipView(
                                label: priority.rawValue,
                                icon: priority.icon,
                                color: priority.color
                            ) { showPriorityPicker = true }
                        }
                        if !tags.isEmpty {
                            ChipView(
                                label: "\(tags.count) tag\(tags.count == 1 ? "" : "s")",
                                icon: "tag"
                            ) { showTagPicker = true }
                        }
                        if let project {
                            ChipView(
                                label: project.title,
                                icon: "folder"
                            ) { showProjectPicker = true }
                        }
                        if !reminderChoices.isEmpty {
                            ChipView(
                                label: "\(reminderChoices.count) reminder\(reminderChoices.count == 1 ? "" : "s")",
                                icon: "bell.fill"
                            ) { showReminderPicker = true }
                        }
                        if let parentTask {
                            ChipView(
                                label: "↳ \(parentTask.title)",
                                icon: "list.bullet.indent"
                            ) { showParentPicker = true }
                        }
                        if recurrence != .none {
                            ChipView(
                                label: recurrence == .custom ? (customRecurrenceRule?.summary ?? "Custom") : recurrence.rawValue,
                                icon: "repeat"
                            ) { showRecurrencePicker = true }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Property buttons + send (order matches TaskRowView: date, priority, reminders, tags, project, recurrence)
            HStack(spacing: 18) {
                Button { showDatePicker = true } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(deadline != nil ? Palette.ink : Palette.muted)
                }
                Button { showPlannedDayPicker = true } label: {
                    Image(systemName: "scope")
                        .foregroundStyle(plannedDay != nil ? Palette.ink : Palette.muted)
                }
                Button { showPriorityPicker = true } label: {
                    Image(systemName: "flag")
                        .foregroundStyle(priority?.color ?? Palette.muted)
                }
                Button { showReminderPicker = true } label: {
                    Image(systemName: !reminderChoices.isEmpty ? "bell.fill" : "bell")
                        .foregroundStyle(!reminderChoices.isEmpty ? Palette.ink : Palette.muted)
                }
                Button { showTagPicker = true } label: {
                    Image(systemName: "tag")
                        .foregroundStyle(!tags.isEmpty ? Palette.ink : Palette.muted)
                }
                Button { showProjectPicker = true } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(project != nil ? Palette.ink : Palette.muted)
                }
                Button { showParentPicker = true } label: {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(parentTask != nil ? Palette.ink : Palette.muted)
                }
                Button { showRecurrencePicker = true } label: {
                    Image(systemName: "repeat")
                        .foregroundStyle(recurrence != .none ? Palette.ink : Palette.muted)
                }
                Spacer()
                Button {
                    createTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(taskTitle.isEmpty ? Palette.hairline : Palette.ink)
                }
                .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty || syncErrorMessage != nil)
            }
            .font(.title3)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(
            Palette.card
                .ignoresSafeArea(edges: .bottom)
        )
        .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
                .mask(alignment: .top) { Rectangle().frame(height: 24) }
        }
        .onAppear {
            if project == nil, let presetProject {
                project = presetProject
            }
            isFocused = true
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $deadline, hasTime: $deadlineHasTime)
        }
        .sheet(isPresented: $showPlannedDayPicker) {
            DatePickerSheet(selectedDate: $plannedDay)
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: $priority)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: $tags)
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: $project)
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(
                selection: $recurrence,
                customRule: $customRecurrenceRule,
                contextDate: deadline
            )
        }
        .sheet(isPresented: $showReminderPicker) {
            InlineReminderPicker(selectedChoices: $reminderChoices)
        }
        .sheet(isPresented: $showParentPicker) {
            ParentTaskPicker(selection: $parentTask)
        }
    }

    private var hasSelections: Bool {
        deadline != nil || plannedDay != nil || priority != nil || !tags.isEmpty || project != nil || recurrence != .none || !reminderChoices.isEmpty || parentTask != nil
    }

    private func createTask() {
        // Use NLP clean title (strips detected tokens) if NLP detected anything
        let hasNLPDetections = nlpDetectedDate || nlpDetectedPriority || nlpDetectedProject || nlpDetectedTags
        let title: String
        if hasNLPDetections {
            let parsed = TaskTitleParser.parse(taskTitle)
            title = parsed.cleanTitle
        } else {
            title = taskTitle.trimmingCharacters(in: .whitespaces)
        }
        guard !title.isEmpty else { return }

        let task = TaskItem(externalTaskID: UUID().uuidString, title: title)
        let selectedWorkspace = try? modelContext.selectedProviderWorkspace()
        task.providerWorkspaceId = selectedWorkspace?.workspaceId
        task.deadline = deadline
        task.plannedDay = plannedDay
        task.deadlineHasTime = deadline != nil && deadlineHasTime
        task.validatePlannedDay()
        task.priority = priority
        task.tags = tags
        task.project = project
        task.recurrence = recurrence
        task.customRecurrenceRule = customRecurrenceRule
        task.isDirty = true

        if let parent = parentTask {
            task.parentId = parent.externalTaskID
            task.parent = parent
            task.sortIndex = parent.subtasks.count
        }

        modelContext.insert(task)

        if let parent = parentTask {
            SubtaskScheduler.distributeSubtaskDates(parent: parent)
        }

        task.taskReminders = reminderChoices.map { $0.toTaskReminder(hasPlannedDay: plannedDay != nil) }

        if !task.taskReminders.isEmpty {
            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        }

        let context = modelContext
        Task {
            do {
                try await taskProvider.submitPendingChanges(for: [task], store: context)
            } catch {
                syncErrorMessage = error.localizedDescription
            }
        }

        // Reset for next task
        taskTitle = ""
        deadline = nil
        plannedDay = nil
        deadlineHasTime = false
        priority = nil
        tags = []
        if presetProject == nil { project = nil }
        recurrence = .none
        reminderChoices = []
        parentTask = nil
        customRecurrenceRule = nil
        nlpDetectedDate = false
        nlpDetectedPriority = false
        nlpDetectedProject = false
        nlpDetectedTags = false
        showProjectSuggestions = false
        showTagSuggestions = false
    }

    // MARK: - NLP Parsing

    private func handleNLPParsing(_ text: String) {
        let result = TaskTitleParser.parse(text)

        // Auto-populate date if not manually set
        if let detected = result.detectedDate, !nlpDetectedDate, deadline == nil {
            deadline = detected
            nlpDetectedDate = true
        } else if result.detectedDate == nil && nlpDetectedDate {
            // User removed the date keyword
            deadline = nil
            nlpDetectedDate = false
        }

        // Auto-populate priority
        if let detected = result.detectedPriority, !nlpDetectedPriority, priority == nil {
            priority = detected
            nlpDetectedPriority = true
        } else if result.detectedPriority == nil && nlpDetectedPriority {
            priority = nil
            nlpDetectedPriority = false
        }

        // Auto-populate project from name
        if let name = result.detectedProjectName, !nlpDetectedProject, project == nil {
            if let matched = selectedProjects.first(where: { $0.title.localizedCaseInsensitiveContains(name) }) {
                project = matched
                nlpDetectedProject = true
            }
        } else if result.detectedProjectName == nil && nlpDetectedProject {
            project = nil
            nlpDetectedProject = false
        }

        // Auto-populate tags
        if !result.detectedTags.isEmpty && !nlpDetectedTags && tags.isEmpty {
            tags = result.detectedTags
            nlpDetectedTags = true
        } else if result.detectedTags.isEmpty && nlpDetectedTags {
            tags = []
            nlpDetectedTags = false
        }
    }

    private func formatPlanningDate(_ date: Date, hasTime: Bool) -> String {
        date.formatted(
            date: .abbreviated,
            time: hasTime ? .shortened : .omitted
        )
    }

    // MARK: - Inline Suggestions

    private func updateSuggestions(_ text: String) {
        // Check for @ trigger
        if let atIndex = text.lastIndex(of: "@") {
            let afterAt = String(text[text.index(after: atIndex)...])
            if !afterAt.contains(" ") || afterAt.isEmpty {
                let query = afterAt.lowercased()
                projectSuggestions = selectedProjects.filter { proj in
                    query.isEmpty || proj.title.lowercased().contains(query)
                }
                showProjectSuggestions = true
                showTagSuggestions = false
                return
            }
        }

        // Check for # trigger
        if let hashIndex = text.lastIndex(of: "#") {
            let afterHash = String(text[text.index(after: hashIndex)...])
            if !afterHash.contains(" ") || afterHash.isEmpty {
                let query = afterHash.lowercased()
                let existingTags = Set(selectedTasks.flatMap(\.tags))
                tagSuggestions = existingTags.filter { tag in
                    query.isEmpty || tag.lowercased().contains(query)
                }.sorted()
                showTagSuggestions = true
                showProjectSuggestions = false
                return
            }
        }

        showProjectSuggestions = false
        showTagSuggestions = false
    }

    private func selectProjectSuggestion(_ proj: ProjectItem) {
        project = proj
        // Remove @query from title
        if let atIndex = taskTitle.lastIndex(of: "@") {
            taskTitle = String(taskTitle[..<atIndex]).trimmingCharacters(in: .whitespaces)
        }
        showProjectSuggestions = false
    }

    private func selectTagSuggestion(_ tag: String) {
        if !tags.contains(tag) {
            tags.append(tag)
        }
        // Remove #query from title
        if let hashIndex = taskTitle.lastIndex(of: "#") {
            taskTitle = String(taskTitle[..<hashIndex]).trimmingCharacters(in: .whitespaces)
        }
        showTagSuggestions = false
    }
}
