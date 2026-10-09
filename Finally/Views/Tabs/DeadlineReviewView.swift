import SwiftUI
import SwiftData

struct DeadlineReviewView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false
        },
        sort: \TaskItem.deadline
    )
    private var nonDoneTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
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

    private var selectedWorkspace: UserSession? { sessions.selectedProviderWorkspace }

    private var deadlineTasks: [TaskItem] {
        nonDoneTasks.filter { $0.belongs(to: selectedWorkspace) && $0.deadline != nil }
    }

    private var overdueTasks: [TaskItem] {
        sortStack.sorted(deadlineTasks.filter { $0.isOverdue })
    }

    private var todayTasks: [TaskItem] {
        sortStack.sorted(deadlineTasks.filter { $0.isDeadlineToday })
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
                        if !overdueTasks.isEmpty {
                            Section {
                                if expandedSections.contains("Overdue") {
                                    ForEach(overdueTasks, id: \.externalTaskID) { task in
                                        taskRow(task)
                                    }
                                }
                            } header: {
                                collapsibleHeader("Overdue")
                            }
                        }
                        Section {
                            if expandedSections.contains("Today") {
                                if todayTasks.isEmpty {
                                    Label("No deadlines today", systemImage: "sun.max")
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(todayTasks, id: \.externalTaskID) { task in
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
            .animation(.default, value: todayTasks.map(\.externalTaskID))
            .animation(.default, value: overdueTasks.map(\.externalTaskID))
            .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "Deadlines")
            .refreshable {
                try? await taskProvider.synchronize(.launch, store: modelContext)
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
