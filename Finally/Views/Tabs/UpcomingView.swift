import SwiftUI
import SwiftData

struct UpcomingView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false && task.deadline != nil
        },
        sort: \TaskItem.deadline
    )
    private var allFutureTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var expandedSections: Set<String> = []
    @State private var isSelectionMode = false
    @State private var selectedTasks: Set<String> = []
    @State private var showSearch = false
    @State private var showSortConfig = false
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString

    private var sortStack: SortStack {
        SortStack.from(sortStackJSON)
    }

    private var upcomingTasks: [TaskItem] {
        allFutureTasks.filter {
            $0.belongs(to: sessions.selectedProviderWorkspace) &&
                ($0.deadline ?? .distantFuture) > Date() &&
                !$0.isSubtask
        }
    }

    private var groupedByDate: [(String, [TaskItem])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let grouped = Dictionary(grouping: upcomingTasks) { task -> String in
            guard let date = task.deadline else { return "No Date" }
            return formatter.string(from: date)
        }

        return grouped.sorted { lhs, rhs in
            let lhsDate = lhs.value.first?.deadline ?? .distantFuture
            let rhsDate = rhs.value.first?.deadline ?? .distantFuture
            return lhsDate < rhsDate
        }.map { (key, tasks) in
            (key, sortStack.sorted(tasks))
        }
    }

    var body: some View {
        NavigationStack {
            if taskProvider.isSyncing && allFutureTasks.isEmpty {
                // First-load sync: replace content entirely
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Syncing your tasks…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Upcoming")
            } else {
                List {
                    ForEach(groupedByDate, id: \.0) { dateString, tasks in
                        Section {
                            if expandedSections.contains(dateString) {
                                ForEach(tasks, id: \.externalTaskID) { task in
                                    taskRow(task)
                                }
                            }
                        } header: {
                            Button {
                                withAnimation {
                                    if expandedSections.contains(dateString) {
                                        expandedSections.remove(dateString)
                                    } else {
                                        expandedSections.insert(dateString)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: expandedSections.contains(dateString) ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                    Text(dateString)
                                }
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "Upcoming")
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
            .overlay {
                if upcomingTasks.isEmpty {
                    ContentUnavailableView(
                        "No upcoming tasks",
                        systemImage: "calendar",
                        description: Text("Tasks with deadlines will appear here")
                    )
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
        }
    }

    // MARK: - Reusable Row

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
        .listRowBackground(
            isSelectionMode && selectedTasks.contains(task.externalTaskID)
                ? Color.blue.opacity(0.15)
                : Color(.systemBackground)
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

    // MARK: - Bulk Actions

    private func bulkDeleteTasks() {
        let tasksToDelete = allFutureTasks.filter { selectedTasks.contains($0.externalTaskID) }
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
        let tasksToComplete = allFutureTasks.filter { selectedTasks.contains($0.externalTaskID) }
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
