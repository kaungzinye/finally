import SwiftUI
import SwiftData

struct UpcomingView: View {
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false && task.dueDate != nil
        },
        sort: \TaskItem.dueDate
    )
    private var allFutureTasks: [TaskItem]
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var expandedSections: Set<String> = []

    private var upcomingTasks: [TaskItem] {
        allFutureTasks.filter { $0.dueDate ?? .distantFuture > Date() }
    }

    private var groupedByDate: [(String, [TaskItem])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let grouped = Dictionary(grouping: upcomingTasks) { task -> String in
            guard let date = task.dueDate else { return "No Date" }
            return formatter.string(from: date)
        }

        return grouped.sorted { lhs, rhs in
            let lhsDate = lhs.value.first?.dueDate ?? .distantFuture
            let rhsDate = rhs.value.first?.dueDate ?? .distantFuture
            return lhsDate < rhsDate
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByDate, id: \.0) { dateString, tasks in
                    Section {
                        if expandedSections.contains(dateString) {
                            ForEach(tasks, id: \.notionPageId) { task in
                                TaskRowView(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTask = task }
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
            .navigationTitle("Upcoming")
            .refreshable {
                await syncService.syncOnLaunch(modelContext: modelContext)
            }
            .overlay {
                if upcomingTasks.isEmpty {
                    ContentUnavailableView(
                        "No upcoming tasks",
                        systemImage: "calendar",
                        description: Text("Tasks with due dates will appear here")
                    )
                }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
        }
    }
}
