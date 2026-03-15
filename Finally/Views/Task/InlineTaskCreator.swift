import SwiftUI
import SwiftData

struct InlineTaskCreator: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query(sort: \ProjectItem.title) private var allProjects: [ProjectItem]
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var allTasks: [TaskItem]

    @State private var taskTitle = ""
    @State private var dueDate: Date?
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
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
    @State private var showReminderPicker = false
    @State private var showParentPicker = false

    @FocusState private var isFocused: Bool

    var presetProject: ProjectItem?

    var body: some View {
        VStack(spacing: 10) {
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
                        ForEach(projectSuggestions.prefix(5), id: \.notionPageId) { proj in
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
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
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.15))
                                    .clipShape(Capsule())
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
                        if let dueDate {
                            ChipView(
                                label: dueDate.formatted(date: .abbreviated, time: .omitted),
                                icon: "calendar",
                                color: .secondary
                            ) { showDatePicker = true }
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
                                icon: "tag",
                                color: .purple
                            ) { showTagPicker = true }
                        }
                        if let project {
                            ChipView(
                                label: project.title,
                                icon: "folder",
                                color: .secondary
                            ) { showProjectPicker = true }
                        }
                        if !reminderChoices.isEmpty {
                            ChipView(
                                label: "\(reminderChoices.count) reminder\(reminderChoices.count == 1 ? "" : "s")",
                                icon: "bell.fill",
                                color: .orange
                            ) { showReminderPicker = true }
                        }
                        if let parentTask {
                            ChipView(
                                label: "↳ \(parentTask.title)",
                                icon: "list.bullet.indent",
                                color: .blue
                            ) { showParentPicker = true }
                        }
                        if recurrence != .none {
                            ChipView(
                                label: recurrence == .custom ? (customRecurrenceRule?.summary ?? "Custom") : recurrence.rawValue,
                                icon: "repeat",
                                color: .green
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
                        .foregroundStyle(dueDate != nil ? .primary : .secondary)
                }
                Button { showPriorityPicker = true } label: {
                    Image(systemName: "flag")
                        .foregroundStyle(priority != nil ? priority!.color : .secondary)
                }
                Button { showReminderPicker = true } label: {
                    Image(systemName: !reminderChoices.isEmpty ? "bell.fill" : "bell")
                        .foregroundStyle(!reminderChoices.isEmpty ? .orange : .secondary)
                }
                Button { showTagPicker = true } label: {
                    Image(systemName: "tag")
                        .foregroundStyle(!tags.isEmpty ? .purple : .secondary)
                }
                Button { showProjectPicker = true } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(project != nil ? .primary : .secondary)
                }
                Button { showParentPicker = true } label: {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(parentTask != nil ? .blue : .secondary)
                }
                Button { showRecurrencePicker = true } label: {
                    Image(systemName: "repeat")
                        .foregroundStyle(recurrence != .none ? .green : .secondary)
                }
                Spacer()
                Button {
                    createTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(taskTitle.isEmpty ? Color.secondary : Color.primary)
                }
                .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.title3)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(
            Color(.secondarySystemBackground)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        )
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .onAppear {
            if project == nil, let presetProject {
                project = presetProject
            }
            isFocused = true
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $dueDate)
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
                contextDate: dueDate
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
        dueDate != nil || priority != nil || !tags.isEmpty || project != nil || recurrence != .none || !reminderChoices.isEmpty || parentTask != nil
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

        let task = TaskItem(notionPageId: UUID().uuidString, title: title)
        task.dueDate = dueDate
        task.priority = priority
        task.tags = tags
        task.project = project
        task.recurrence = recurrence
        task.customRecurrenceRule = customRecurrenceRule
        task.isDirty = true

        // Link as subtask if parent selected
        if let parent = parentTask {
            task.parentId = parent.notionPageId
            task.parent = parent
            task.isLocalOnly = true
            task.sortIndex = parent.subtasks.count
        }

        modelContext.insert(task)

        // Schedule subtask dates if linked to parent
        if let parent = parentTask {
            SubtaskScheduler.distributeSubtaskDates(parent: parent)
        }

        // Create reminders from selected choices
        for choice in reminderChoices {
            let reminder: ReminderItem
            switch choice {
            case .preset(let offset):
                reminder = ReminderItem(
                    intervalSeconds: offset.intervalSeconds,
                    label: offset.rawValue,
                    taskNotionPageId: task.notionPageId
                )
            case .custom(let date):
                reminder = ReminderItem(
                    absoluteDate: date,
                    label: date.formatted(date: .abbreviated, time: .shortened),
                    taskNotionPageId: task.notionPageId
                )
            }
            reminder.task = task
            modelContext.insert(reminder)
        }

        // Schedule notifications if we have reminders
        if !reminderChoices.isEmpty {
            NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
        }

        // Push to Notion in background
        let context = modelContext
        Task {
            if let session = try? context.fetch(FetchDescriptor<UserSession>()).first {
                try? await syncService.pushDirtyChanges(session: session, modelContext: context)
            }
        }

        // Reset for next task
        taskTitle = ""
        dueDate = nil
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
        if let detected = result.detectedDate, !nlpDetectedDate, dueDate == nil {
            dueDate = detected
            nlpDetectedDate = true
        } else if result.detectedDate == nil && nlpDetectedDate {
            // User removed the date keyword
            dueDate = nil
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
            if let matched = allProjects.first(where: { $0.title.localizedCaseInsensitiveContains(name) }) {
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

    // MARK: - Inline Suggestions

    private func updateSuggestions(_ text: String) {
        // Check for @ trigger
        if let atIndex = text.lastIndex(of: "@") {
            let afterAt = String(text[text.index(after: atIndex)...])
            if !afterAt.contains(" ") || afterAt.isEmpty {
                let query = afterAt.lowercased()
                projectSuggestions = allProjects.filter { proj in
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
                let existingTags = Set(allTasks.flatMap(\.tags))
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
