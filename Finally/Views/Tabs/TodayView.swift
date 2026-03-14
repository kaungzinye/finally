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
