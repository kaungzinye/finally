import SwiftUI
import SwiftData

struct KanbanView: View {
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var allTasks: [TaskItem]
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var showSearch = false
    @State private var showFilterSheet = false
    @State private var draggingTaskId: String?
    @State private var filterProjects: Set<String> = []
    @State private var filterPriorities: Set<String> = []

    private var topLevelTasks: [TaskItem] {
        allTasks.filter { !$0.isSubtask }
    }

    private var filteredTasks: [TaskItem] {
        topLevelTasks.filter { task in
            (filterProjects.isEmpty || filterProjects.contains(task.project?.notionPageId ?? "")) &&
            (filterPriorities.isEmpty || filterPriorities.contains(task.priorityRaw ?? ""))
        }
    }

    private var hasActiveFilters: Bool {
        !filterProjects.isEmpty || !filterPriorities.isEmpty
    }

    private var notStartedTasks: [TaskItem] {
        filteredTasks.filter { $0.status == .notStarted }
    }

    private var inProgressTasks: [TaskItem] {
        filteredTasks.filter { $0.status == .inProgress }
    }

    private var doneTasks: [TaskItem] {
        filteredTasks.filter { $0.status == .done }
    }

    var body: some View {
        NavigationStack {
            Group {
                if syncService.isSyncing && allTasks.isEmpty {
                    // First-load sync: replace content entirely
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing your tasks…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        let isLandscape = geo.size.width > geo.size.height
                        let columnWidth = isLandscape ? geo.size.width * 0.32 : geo.size.width * 0.48

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                kanbanColumn("To Do", color: .blue, status: .notStarted, tasks: notStartedTasks, width: columnWidth, isLandscape: isLandscape)
                                kanbanColumn("In Progress", color: .orange, status: .inProgress, tasks: inProgressTasks, width: columnWidth, isLandscape: isLandscape)
                                kanbanColumn("Done", color: .green, status: .done, tasks: doneTasks, width: columnWidth, isLandscape: isLandscape)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Board")
            .refreshable {
                await syncService.syncOnLaunch(modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showFilterSheet = true } label: {
                            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchFilterView()
            }
            .sheet(isPresented: $showFilterSheet) {
                KanbanFilterView(
                    filterProjects: $filterProjects,
                    filterPriorities: $filterPriorities
                )
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.fraction(0.8)])
            }
        }
    }

    // MARK: - Column

    @ViewBuilder
    private func kanbanColumn(_ title: String, color: Color, status: TaskStatus, tasks: [TaskItem], width: CGFloat, isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Cards
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(tasks, id: \.notionPageId) { task in
                                kanbanCard(task, isLandscape: isLandscape)
                            .draggable(task.notionPageId) {
                                // Drag preview
                                Text(task.title)
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .shadow(radius: 4)
                                    .onAppear {
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        draggingTaskId = task.notionPageId
                                    }
                            }
                            .opacity(draggingTaskId == task.notionPageId ? 0.4 : 1.0)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: width)
        // Column background follows app background, adapting automatically to light/dark mode
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let taskId = droppedIds.first,
                  let task = allTasks.first(where: { $0.notionPageId == taskId }) else { return false }
            withAnimation {
                task.status = status
                task.isDirty = true
            }
            draggingTaskId = nil
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            return true
        } isTargeted: { isTargeted in
            // Could highlight the column when targeted
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func kanbanCard(_ task: TaskItem, isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(task.status == .done ? .secondary : .primary)
                .strikethrough(task.status == .done)

            HStack(spacing: 6) {
                // Due date — match order used in Today/Upcoming
                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(formatDate(dueDate))
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(task.isOverdue ? .red : (task.isInActiveWindow ? .orange : .secondary))
                }

                // Priority
                if let priority = task.priority {
                    Image(systemName: priority.icon)
                        .font(.caption2)
                        .foregroundStyle(priority.color)
                }

                Spacer(minLength: 0)

                // Vertical (portrait) Kanban: only show project in the trailing side
                if !isLandscape {
                    if let emoji = task.project?.iconEmoji {
                        Text(emoji)
                            .font(.caption2)
                    } else if let projectTitle = task.project?.title {
                        Text(projectTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    // Horizontal (landscape) Kanban: show full set of properties like Today/Upcoming
                    HStack(spacing: 6) {
                        if let emoji = task.project?.iconEmoji {
                            Text(emoji)
                                .font(.caption2)
                        } else if let projectTitle = task.project?.title {
                            Text(projectTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if !task.tags.isEmpty {
                            ForEach(Array(task.tags.prefix(1).enumerated()), id: \.offset) { index, tag in
                                let colorName = index < task.tagColors.count ? task.tagColors[index] : "default"
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundStyle(NotionColor.swiftUIColor(for: colorName))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        // Use a single adaptive system background for task rows (matches list rows)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTask = task
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
