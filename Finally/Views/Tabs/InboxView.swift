import SwiftUI
import SwiftData

struct InboxView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false
        },
        sort: \TaskItem.dueDate
    )
    private var allNonDoneTasks: [TaskItem]
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var isSelectionMode = false
    @State private var selectedTasks: Set<String> = []

    private var inboxTasks: [TaskItem] {
        allNonDoneTasks.filter { $0.project == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(inboxTasks, id: \.notionPageId) { task in
                    ZStack(alignment: .leading) {
                        if isSelectionMode && selectedTasks.contains(task.notionPageId) {
                            Color.blue.opacity(0.1)
                        }
                        TaskRowView(task: task)
                    }
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
            }
            .navigationTitle(isSelectionMode ? "Select Tasks (\(selectedTasks.count))" : "Inbox")
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
            .overlay(alignment: .top) {
                if syncService.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.fraction(0.8)])
            }
        }
    }

    private func bulkDeleteTasks() {
        let tasksToDelete = inboxTasks.filter { selectedTasks.contains($0.notionPageId) }
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
        let tasksToComplete = inboxTasks.filter { selectedTasks.contains($0.notionPageId) }
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
