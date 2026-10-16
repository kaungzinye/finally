import SwiftUI
import SwiftData

struct InlineTaskCreator: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Query(sort: \ProjectItem.title) private var allProjects: [ProjectItem]
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var allTasks: [TaskItem]
    @Query private var sessions: [UserSession]

    @State private var draft = CaptureDraft()
    @State private var projectSuggestions: [ProjectItem] = []
    @State private var tagSuggestions: [String] = []
    @State private var showProjectSuggestions = false
    @State private var showTagSuggestions = false

    @State private var showDatePicker = false
    @State private var showScheduledDayPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false
    @State private var showProjectPicker = false
    @State private var showRecurrencePicker = false
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
            TextField("Add a task...", text: $draft.text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .onChange(of: draft.text) { _, newValue in
                    draft.readText(projects: selectedProjects)
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
                        if let deadline = draft.deadline {
                            ChipView(
                                label: "Deadline \(formatPlanningDate(deadline, hasTime: draft.deadlineHasTime))",
                                icon: "calendar"
                            ) { showDatePicker = true }
                        }
                        if let scheduledDay = draft.scheduledDay {
                            ChipView(
                                label: "Scheduled \(formatPlanningDate(scheduledDay, hasTime: false))",
                                icon: "scope"
                            ) { showScheduledDayPicker = true }
                        }
                        if let priority = draft.priority {
                            ChipView(
                                label: priority.rawValue,
                                icon: priority.icon,
                                color: priority.color
                            ) { showPriorityPicker = true }
                        }
                        if !draft.tags.isEmpty {
                            ChipView(
                                label: "\(draft.tags.count) tag\(draft.tags.count == 1 ? "" : "s")",
                                icon: "tag"
                            ) { showTagPicker = true }
                        }
                        if let project = draft.project {
                            ChipView(
                                label: project.title,
                                icon: "folder"
                            ) { showProjectPicker = true }
                        }
                        if let parentTask = draft.parentTask {
                            ChipView(
                                label: "↳ \(parentTask.title)",
                                icon: "list.bullet.indent"
                            ) { showParentPicker = true }
                        }
                        if draft.recurrence != .none {
                            ChipView(
                                label: draft.recurrence == .custom ? (draft.customRecurrenceRule?.summary ?? "Custom") : draft.recurrence.rawValue,
                                icon: "repeat"
                            ) { showRecurrencePicker = true }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Property buttons + send
            HStack(spacing: 18) {
                Button { showDatePicker = true } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(draft.deadline != nil ? Palette.ink : Palette.muted)
                }
                .accessibilityLabel("Deadline")
                Button { showScheduledDayPicker = true } label: {
                    Image(systemName: "scope")
                        .foregroundStyle(draft.scheduledDay != nil ? Palette.ink : Palette.muted)
                }
                .accessibilityLabel("Scheduled")
                Button { showPriorityPicker = true } label: {
                    Image(systemName: "flag")
                        .foregroundStyle(draft.priority?.color ?? Palette.muted)
                }
                .accessibilityLabel("Priority")
                Button { showTagPicker = true } label: {
                    Image(systemName: "tag")
                        .foregroundStyle(!draft.tags.isEmpty ? Palette.ink : Palette.muted)
                }
                .accessibilityLabel("Tags")
                Button { showProjectPicker = true } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(draft.project != nil ? Palette.ink : Palette.muted)
                }
                .accessibilityLabel("Project")
                Button { showParentPicker = true } label: {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(draft.parentTask != nil ? Palette.ink : Palette.muted)
                }
                .accessibilityLabel("Parent task")
                Button { showRecurrencePicker = true } label: {
                    Image(systemName: "repeat")
                        .foregroundStyle(draft.recurrence != .none ? Palette.ink : Palette.muted)
                }
                .accessibilityLabel("Repeat")
                Spacer()
                Button {
                    createTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(draft.text.isEmpty ? Palette.hairline : Palette.ink)
                }
                .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty || syncErrorMessage != nil)
                .accessibilityLabel("Add task")
                .accessibilityIdentifier("send-task")
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
            if draft.project == nil, let presetProject {
                draft.pick(project: presetProject)
            }
            isFocused = true
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(
                deadline: Binding(
                    get: { draft.deadline },
                    set: { draft.pick(deadline: $0, hasTime: draft.deadlineHasTime) }
                ),
                hasTime: Binding(
                    get: { draft.deadlineHasTime },
                    set: { draft.pick(deadline: draft.deadline, hasTime: $0) }
                )
            )
        }
        .sheet(isPresented: $showScheduledDayPicker) {
            DatePickerSheet(scheduledDay: Binding(get: { draft.scheduledDay }, set: { draft.pick(scheduledDay: $0) }))
        }
        .sheet(isPresented: $showPriorityPicker) {
            PriorityPicker(selection: Binding(get: { draft.priority }, set: { draft.pick(priority: $0) }))
        }
        .sheet(isPresented: $showTagPicker) {
            TagPicker(selectedTags: Binding(get: { draft.tags }, set: { draft.pick(tags: $0) }))
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPicker(selection: Binding(get: { draft.project }, set: { draft.pick(project: $0) }))
        }
        .sheet(isPresented: $showRecurrencePicker) {
            RecurrencePicker(
                selection: $draft.recurrence,
                customRule: $draft.customRecurrenceRule,
                contextDate: draft.deadline
            )
        }
        .sheet(isPresented: $showParentPicker) {
            ParentTaskPicker(selection: $draft.parentTask)
        }
    }

    private var hasSelections: Bool {
        draft.deadline != nil || draft.scheduledDay != nil || draft.priority != nil || !draft.tags.isEmpty || draft.project != nil || draft.recurrence != .none || draft.parentTask != nil
    }

    private func createTask() {
        let workspaceId = (try? modelContext.selectedProviderWorkspace())?.workspaceId
        guard let task = draft.makeTask(workspaceId: workspaceId, defaults: .current()) else { return }

        modelContext.insert(task)

        if let parent = draft.parentTask {
            SubtaskScheduler.distributeSubtaskDates(parent: parent)
        }

        if task.hasReminders {
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

        draft = CaptureDraft(project: presetProject)
        showProjectSuggestions = false
        showTagSuggestions = false
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
        draft.pick(project: proj)
        // Remove @query from title
        if let atIndex = draft.text.lastIndex(of: "@") {
            draft.text = String(draft.text[..<atIndex]).trimmingCharacters(in: .whitespaces)
        }
        showProjectSuggestions = false
    }

    private func selectTagSuggestion(_ tag: String) {
        draft.pick(tag: tag)
        // Remove #query from title
        if let hashIndex = draft.text.lastIndex(of: "#") {
            draft.text = String(draft.text[..<hashIndex]).trimmingCharacters(in: .whitespaces)
        }
        showTagSuggestions = false
    }
}
