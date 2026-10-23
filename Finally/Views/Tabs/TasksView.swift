import SwiftData
import SwiftUI

/// The Tasks tab: every open task in the workspace, as a list or as the Board.
/// The list opens with the Inbox, then each project with its nearest tasks.
/// The Board mounts the first time it shows and then stays mounted beside the list under fixed
/// controls, so switching crossfades without rebuilding either. One query feeds both and the
/// project pages.
struct TasksView: View {
    enum Layout: String {
        case list, board
    }

    /// Every task in the store. TasksList and BoardColumns drop deleted ones.
    @Query private var tasks: [TaskItem]
    @Query private var projects: [ProjectItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @AppStorage("tasksLayout") private var layout: Layout = .list
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString
    @State private var unscheduledOnly = false
    @State private var path: [ProjectItem] = []
    @State private var selectedTask: TaskItem?
    @State private var showSearch = false
    @State private var showSortConfig = false
    /// The Board mounts the first time it shows, then stays mounted.
    @State private var hasShownBoard = false

    private var sortStack: SortStack { SortStack.from(sortStackJSON) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                controls
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                ZStack {
                    taskList
                        .shown(layout == .list)
                    if hasShownBoard || layout == .board {
                        BoardView(isActive: layout == .board, allTasks: tasks)
                            .shown(layout == .board)
                            .onAppear { hasShownBoard = true }
                    }
                }
                .animation(.smooth(duration: 0.2), value: layout)
            }
            .background(Palette.paper)
            .navigationTitle("Tasks")
            .navigationDestination(for: ProjectItem.self) { project in
                ProjectTasksView(project: project, tasks: tasks, unscheduledOnly: $unscheduledOnly)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if layout == .list {
                        Button { showSortConfig = true } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Sort")
                    }
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                }
            }
        }
        .onChange(of: sessions.selectedProviderWorkspace?.workspaceId) { _, _ in path = [] }
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
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.fraction(0.8)])
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            layoutChip("List", .list)
            layoutChip("Board", .board)
            FilterChip(title: "Unscheduled", isOn: $unscheduledOnly)
                .accessibilityIdentifier("tasks-filter-unscheduled")
                .shown(layout == .list)
            Spacer(minLength: 0)
        }
        .animation(.smooth(duration: 0.2), value: layout)
    }

    /// A layout as a chip, filled while it shows. Tapping the shown layout keeps it.
    private func layoutChip(_ title: String, _ choice: Layout) -> some View {
        FilterChip(title: title, isOn: Binding(
            get: { layout == choice },
            set: { isOn in if isOn { layout = choice } }
        ))
        .accessibilityIdentifier("tasks-layout-\(choice.rawValue)")
    }

    private var taskList: some View {
        let list = TasksList(
            tasks: tasks, projects: projects,
            workspace: sessions.selectedProviderWorkspace, unscheduledOnly: unscheduledOnly
        )
        return List {
            Section {
                if list.inbox.isEmpty {
                    emptyRow(unscheduledOnly ? "No unscheduled tasks" : "Nothing in Inbox")
                } else {
                    ForEach(sortStack.sorted(list.inbox), id: \.externalTaskID) { task in
                        row(task)
                    }
                }
            } header: {
                SectionLabel(title: "Inbox") { Text("\(list.inbox.count)") }
                    .accessibilityIdentifier("tasks-inbox-header")
            }

            ForEach(list.projects) { group in
                Section {
                    ForEach(group.nearest, id: \.externalTaskID) { task in
                        row(task)
                    }
                    if group.moreCount > 0 {
                        Button { path.append(group.project) } label: {
                            HStack {
                                Text("+\(group.moreCount) more")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .imageScale(.small)
                            }
                            .font(.meta)
                            .foregroundStyle(Palette.muted)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                        .accessibilityIdentifier("tasks-more-\(group.id)")
                    }
                    if group.tasks.isEmpty {
                        emptyRow("No open tasks")
                    }
                } header: {
                    Button { path.append(group.project) } label: {
                        SectionLabel(title: projectTitle(group.project)) {
                            Image(systemName: "chevron.right")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tasks-project-\(group.id)")
                }
            }
        }
        .paperList()
        .refreshable {
            try? await taskProvider.synchronize(.launch, store: modelContext)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
            .contentShape(Rectangle())
            .onTapGesture { selectedTask = task }
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.meta)
            .foregroundStyle(Palette.muted)
            .cardRow()
    }

    private func projectTitle(_ project: ProjectItem) -> String {
        [project.iconEmoji, project.title].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Project

/// One project's open tasks in the user's sort order, opened from Tasks.
struct ProjectTasksView: View {
    let project: ProjectItem
    /// The Tasks tab's tasks, from its one query.
    let tasks: [TaskItem]
    @Binding var unscheduledOnly: Bool

    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(NavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString

    @State private var selectedTask: TaskItem?

    private var projectTasks: [TaskItem] {
        let list = TasksList(
            tasks: tasks, projects: [project],
            workspace: sessions.selectedProviderWorkspace, unscheduledOnly: unscheduledOnly
        )
        return SortStack.from(sortStackJSON).sorted(list.projects.first?.tasks ?? [])
    }

    var body: some View {
        List {
            HStack {
                FilterChip(title: "Unscheduled", isOn: $unscheduledOnly)
                Spacer(minLength: 0)
            }
            .controlsRow()

            Section {
                ForEach(projectTasks, id: \.externalTaskID) { task in
                    TaskRowView(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
                }
            }
        }
        .paperList()
        .navigationTitle(project.title)
        .onAppear { router.creatorProject = project }
        .onDisappear { router.creatorProject = nil }
        .refreshable {
            try? await taskProvider.synchronize(.launch, store: modelContext)
        }
        .overlay {
            if projectTasks.isEmpty {
                ContentUnavailableView(
                    unscheduledOnly ? "No unscheduled tasks" : "No open tasks",
                    systemImage: "checkmark.circle"
                )
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.fraction(0.8)])
        }
    }
}

// MARK: - Controls

private extension View {
    /// A row on paper whose leading edge lines up with the cards below it.
    func controlsRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}

private extension View {
    /// Shows or hides a view that stays mounted, so it keeps its state and skips a rebuild.
    func shown(_ isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }
}
