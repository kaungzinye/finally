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
                    Section {
                        if expandedSections.contains("Overdue") {
                            ForEach(overdueTasks, id: \.notionPageId) { task in
                                TaskRowView(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTask = task }
                            }
                        }
                    } header: {
                        Button {
                            withAnimation {
                                if expandedSections.contains("Overdue") {
                                    expandedSections.remove("Overdue")
                                } else {
                                    expandedSections.insert("Overdue")
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: expandedSections.contains("Overdue") ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                Text("Overdue")
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    if expandedSections.contains("Today") {
                        ForEach(todayTasks, id: \.notionPageId) { task in
                            TaskRowView(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTask = task }
                        }
                    }
                } header: {
                    Button {
                        withAnimation {
                            if expandedSections.contains("Today") {
                                expandedSections.remove("Today")
                            } else {
                                expandedSections.insert("Today")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: expandedSections.contains("Today") ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("Today")
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
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
            }
        }
    }
}
