import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false
        },
        sort: \TaskItem.deadline
    )
    private var nonDoneTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(DailyFocusService.self) private var dailyFocusService
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppConstants.focusLimitKey) private var focusLimit = DailyFocus.defaultFocusLimit

    @State private var dailyFocus: DailyFocus?
    @State private var selectedTask: TaskItem?
    @State private var expandedSections: Set<String> = ["Deadlines today"]
    @State private var isSelectionMode = false
    @State private var selectedTasks: Set<String> = []
    @State private var showSearch = false
    @State private var showSortConfig = false
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString

    private var sortStack: SortStack {
        get { SortStack.from(sortStackJSON) }
    }

    /// Visible tasks: hide parents with active subtasks, include subtasks with actionable suggestedDate
    private var visibleTasks: [TaskItem] {
        nonDoneTasks.filter { task in
            guard task.belongs(to: selectedWorkspace) else { return false }
            // Hide parents that have incomplete subtasks (Trojan Horse)
            if task.hasSubtasks && !task.allSubtasksComplete { return false }
            return true
        }
    }

    /// Subtasks from any parent whose suggestedDate is today or overdue
    private var actionableSubtasks: [TaskItem] {
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: Date().addingTimeInterval(86400))
        return nonDoneTasks.filter { task in
            guard task.belongs(to: selectedWorkspace) else { return false }
            guard task.isSubtask, let suggested = task.suggestedDate else { return false }
            return suggested < endOfToday
        }
    }

    private var selectedWorkspace: UserSession? { sessions.selectedProviderWorkspace }

    private var overdueTasks: [TaskItem] {
        let parentOverdue = sortStack.sorted(visibleTasks.filter { $0.isOverdue && !$0.isSubtask })
        let subtaskOverdue = sortStack.sorted(actionableSubtasks.filter {
            guard let suggested = $0.suggestedDate else { return false }
            return suggested < Calendar.current.startOfDay(for: Date())
        })
        return parentOverdue + subtaskOverdue
    }

    private var todayTasks: [TaskItem] {
        let parentToday = sortStack.sorted(visibleTasks.filter { $0.isDeadlineToday && !$0.isSubtask })
        let subtaskToday = sortStack.sorted(actionableSubtasks.filter {
            guard let suggested = $0.suggestedDate else { return false }
            return Calendar.current.isDateInToday(suggested)
        })
        return parentToday + subtaskToday
    }

    var body: some View {
        NavigationStack {
            Group {
                if taskProvider.isSyncing && nonDoneTasks.isEmpty {
                    // First-load sync: replace content entirely
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing your tasks…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        TodayHeader(focus: dailyFocus)
                            .paperRow()
                        if let dailyFocus {
                            DailyFocusSection(
                                focus: dailyFocus,
                                onChange: saveDailyFocus,
                                onSelectTask: { selectedTask = $0 }
                            )
                        }
                        if !overdueTasks.isEmpty {
                            Section {
                                if expandedSections.contains("Overdue") {
                                    ForEach(overdueTasks, id: \.externalTaskID) { task in
                                        taskRow(task)
                                    }
                                }
                            } header: {
                                collapsibleHeader("Overdue", count: overdueTasks.count)
                            }
                        }
                        Section {
                            if expandedSections.contains("Deadlines today") {
                                if todayTasks.isEmpty {
                                    Label("No deadlines today", systemImage: "sun.max")
                                        .foregroundStyle(Palette.muted)
                                        .cardRow()
                                }
                                ForEach(todayTasks, id: \.externalTaskID) { task in
                                    taskRow(task)
                                }
                            }
                        } header: {
                            collapsibleHeader("Deadlines today", count: todayTasks.count)
                        }
                    }
                    .paperList()
                }
            }
            .animation(.default, value: todayTasks.map(\.externalTaskID))
            .animation(.default, value: overdueTasks.map(\.externalTaskID))
            .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                try? await taskProvider.synchronize(.launch, store: modelContext)
                await loadDailyFocus()
            }
            .task(id: selectedWorkspace?.workspaceId) {
                await loadDailyFocus()
            }
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            withAnimation {
                                isSelectionMode = false
                                selectedTasks.removeAll()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                bulkDeleteTasks()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(selectedTasks.isEmpty)

                            Button {
                                bulkCompleteTasks()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .disabled(selectedTasks.isEmpty)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button { showSortConfig = true } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }

                            Button { showSearch = true } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.fraction(0.8)])
        }
        .sheet(isPresented: $showSearch) {
            SearchFilterView()
        }
        .sheet(isPresented: $showSortConfig) {
            SortConfigView(sortStack: Binding(
                get: { SortStack.from(sortStackJSON) },
                set: { sortStackJSON = $0.jsonString }
            ))
            .presentationDetents([.medium])
        }
    }

    // MARK: - Daily Focus

    private func loadDailyFocus() async {
        dailyFocus = try? await dailyFocusService.dailyFocus(
            for: Date(),
            workspace: selectedWorkspace,
            store: modelContext,
            focusLimit: focusLimit
        )
    }

    private func saveDailyFocus() {
        guard let dailyFocus else { return }
        Task {
            try? await dailyFocusService.save(dailyFocus, workspace: selectedWorkspace, store: modelContext)
        }
    }

    // MARK: - Reusable Row

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
        .listRowBackground(
            isSelectionMode && selectedTasks.contains(task.externalTaskID)
                ? Palette.selection
                : Palette.card
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                if selectedTasks.contains(task.externalTaskID) {
                    selectedTasks.remove(task.externalTaskID)
                } else {
                    selectedTasks.insert(task.externalTaskID)
                }
            } else {
                selectedTask = task
            }
        }
        .onLongPressGesture {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            withAnimation {
                isSelectionMode = true
                selectedTasks.insert(task.externalTaskID)
            }
        }
    }

    // MARK: - Collapsible Header

    private func collapsibleHeader(_ title: String, count: Int) -> some View {
        Button {
            withAnimation {
                if expandedSections.contains(title) {
                    expandedSections.remove(title)
                } else {
                    expandedSections.insert(title)
                }
            }
        } label: {
            SectionLabel(title: title) {
                HStack(spacing: 6) {
                    Text("\(count)")
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expandedSections.contains(title) ? 90 : 0))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk Actions

    private func bulkDeleteTasks() {
        let tasksToDelete = nonDoneTasks.filter { selectedTasks.contains($0.externalTaskID) }
        for task in tasksToDelete {
            task.isDeleted = true
            task.isDirty = true
        }
        submitMutations(tasksToDelete)
        withAnimation {
            isSelectionMode = false
            selectedTasks.removeAll()
        }
    }

    private func bulkCompleteTasks() {
        let tasksToComplete = nonDoneTasks.filter { selectedTasks.contains($0.externalTaskID) }
        for task in tasksToComplete {
            let recycled = task.complete()
            if recycled {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task)
            }
        }
        submitMutations(tasksToComplete)
        withAnimation {
            isSelectionMode = false
            selectedTasks.removeAll()
        }
    }

    private func submitMutations(_ tasks: [TaskItem]) {
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: tasks, store: modelContext)
        }
    }
}

/// The page heading: the weekday, the date, and how much of the Daily Focus is done.
private struct TodayHeader: View {
    let focus: DailyFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today · \(Date.now.formatted(.dateTime.weekday(.wide)))".uppercased())
                .font(.eyebrow)
                .tracking(0.5)
                .foregroundStyle(Palette.muted)
            Text(Date.now.formatted(.dateTime.day().month(.wide)))
                .font(.pageTitle)
                .foregroundStyle(Palette.ink)
            if let focus, !focus.picks.isEmpty {
                DailyFocusProgress(focus: focus)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}
