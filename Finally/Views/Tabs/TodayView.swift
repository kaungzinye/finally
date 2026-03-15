import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false
        },
        sort: \TaskItem.dueDate
    )
    private var nonDoneTasks: [TaskItem]
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var expandedSections: Set<String> = ["Today"]
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
            guard task.isSubtask, let suggested = task.suggestedDate else { return false }
            return suggested < endOfToday
        }
    }

    private var overdueTasks: [TaskItem] {
        let parentOverdue = sortStack.sorted(visibleTasks.filter { $0.isOverdue && !$0.isSubtask })
        let subtaskOverdue = sortStack.sorted(actionableSubtasks.filter {
            guard let suggested = $0.suggestedDate else { return false }
            return suggested < Calendar.current.startOfDay(for: Date())
        })
        return parentOverdue + subtaskOverdue
    }

    private var todayTasks: [TaskItem] {
        let parentToday = sortStack.sorted(visibleTasks.filter { $0.isDueToday && !$0.isSubtask })
        let subtaskToday = sortStack.sorted(actionableSubtasks.filter {
            guard let suggested = $0.suggestedDate else { return false }
            return Calendar.current.isDateInToday(suggested)
        })
        return parentToday + subtaskToday
    }

    var body: some View {
        NavigationStack {
            Group {
                if syncService.isSyncing && nonDoneTasks.isEmpty {
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
                        if !overdueTasks.isEmpty {
                            Section {
                                if expandedSections.contains("Overdue") {
                                    ForEach(overdueTasks, id: \.notionPageId) { task in
                                        taskRow(task)
                                    }
                                }
                            } header: {
                                collapsibleHeader("Overdue")
                            }
                        }
                        Section {
                            if expandedSections.contains("Today") {
                                ForEach(todayTasks, id: \.notionPageId) { task in
                                    taskRow(task)
                                }
                            }
                        } header: {
                            collapsibleHeader("Today")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .animation(.default, value: todayTasks.map(\.notionPageId))
            .animation(.default, value: overdueTasks.map(\.notionPageId))
            .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "Today")
            .refreshable {
                await syncService.syncOnLaunch(modelContext: modelContext)
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
            .overlay {
                if overdueTasks.isEmpty && todayTasks.isEmpty {
                    ContentUnavailableView(
                        "All clear!",
                        systemImage: "sun.max",
                        description: Text("No tasks due today")
                    )
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

    // MARK: - Reusable Row

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
        .listRowBackground(
            isSelectionMode && selectedTasks.contains(task.notionPageId)
                ? Color.blue.opacity(0.15)
                : Color(.systemBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                if selectedTasks.contains(task.notionPageId) {
                    selectedTasks.remove(task.notionPageId)
                } else {
                    selectedTasks.insert(task.notionPageId)
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
                selectedTasks.insert(task.notionPageId)
            }
        }
    }

    // MARK: - Collapsible Header

    private func collapsibleHeader(_ title: String) -> some View {
        Button {
            withAnimation {
                if expandedSections.contains(title) {
                    expandedSections.remove(title)
                } else {
                    expandedSections.insert(title)
                }
            }
        } label: {
            HStack {
                Image(systemName: expandedSections.contains(title) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                Text(title)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk Actions

    private func bulkDeleteTasks() {
        let tasksToDelete = nonDoneTasks.filter { selectedTasks.contains($0.notionPageId) }
        for task in tasksToDelete {
            task.isDeleted = true
            task.isDirty = true
        }
        try? modelContext.save()
        withAnimation {
            isSelectionMode = false
            selectedTasks.removeAll()
        }
    }

    private func bulkCompleteTasks() {
        let tasksToComplete = nonDoneTasks.filter { selectedTasks.contains($0.notionPageId) }
        for task in tasksToComplete {
            let recycled = task.complete()
            if recycled {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task)
            }
        }
        try? modelContext.save()
        withAnimation {
            isSelectionMode = false
            selectedTasks.removeAll()
        }
    }
}
