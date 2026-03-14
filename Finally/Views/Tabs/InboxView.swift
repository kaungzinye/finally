import SwiftUI
import SwiftData

struct InboxView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Done" && task.isDeleted == false
        },
        sort: \TaskItem.dueDate
    )
    private var allNonDoneTasks: [TaskItem]
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?

    private var inboxTasks: [TaskItem] {
        allNonDoneTasks.filter { $0.project == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(inboxTasks, id: \.notionPageId) { task in
                    TaskRowView(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
                }
            }
            .navigationTitle("Inbox")
            .refreshable {
                await syncService.syncOnLaunch(modelContext: modelContext)
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
            }
        }
    }
}
