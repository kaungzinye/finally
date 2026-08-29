import SwiftUI
import SwiftData

struct InboxView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false
        },
        sort: \TaskItem.deadline
    )
    private var allNonDoneTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var isSelectionMode = false
    @State private var selectedTasks: Set<String> = []

    private var inboxTasks: [TaskItem] {
        allNonDoneTasks.filter {
            $0.belongs(to: sessions.selectedProviderWorkspace) && $0.project == nil
        }
    }

    var body: some View {
        NavigationStack {
            if taskProvider.isSyncing && allNonDoneTasks.isEmpty {
                // First-load sync: replace content entirely
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Syncing your tasks…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Inbox")
            } else {
                List {
                    ForEach(inboxTasks, id: \.externalTaskID) { task in
                        ZStack(alignment: .leading) {
                            if isSelectionMode && selectedTasks.contains(task.externalTaskID) {
                                Color.blue.opacity(0.1)
                            }
                            TaskRowView(task: task)
                        }
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
                }
                .listStyle(.plain)
                .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "Inbox")
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
                    }
                }
                .overlay {
                    if inboxTasks.isEmpty {
                        ContentUnavailableView(
                            "No tasks in Inbox",
                            systemImage: "tray",
                            description: Text("Tasks without a project will appear here")
                        )
                    }
                }
                .sheet(item: $selectedTask) { task in
                    TaskDetailView(task: task)
                        .presentationDetents([.fraction(0.8)])
                }
            }
        }
    }

    private func bulkDeleteTasks() {
        let tasksToDelete = inboxTasks.filter { selectedTasks.contains($0.externalTaskID) }
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
        let tasksToComplete = inboxTasks.filter { selectedTasks.contains($0.externalTaskID) }
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
