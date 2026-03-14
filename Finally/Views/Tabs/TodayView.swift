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

    private var overdueTasks: [TaskItem] {
        nonDoneTasks.filter { $0.isOverdue }
    }

    private var todayTasks: [TaskItem] {
        nonDoneTasks.filter { $0.isDueToday }
    }

    var body: some View {
        NavigationStack {
            List {
                if !overdueTasks.isEmpty {
                    Section("Overdue") {
                        ForEach(overdueTasks, id: \.notionPageId) { task in
                            TaskRowView(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTask = task }
                        }
                    }
                }
                Section("Today") {
                    ForEach(todayTasks, id: \.notionPageId) { task in
                        TaskRowView(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTask = task }
                    }
                }
            }
            .navigationTitle("Today")
            .refreshable {
                await syncService.syncOnLaunch(modelContext: modelContext)
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
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
        }
    }
}
