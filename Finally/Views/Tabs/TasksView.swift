import SwiftData
import SwiftUI

/// The Tasks tab: every open task in the workspace, as a list or as the Board.
/// The list opens with the Inbox, then each project with its nearest tasks.
struct TasksView: View {
    enum Layout: String {
        case list, board
    }

    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var tasks: [TaskItem]
    @Query private var projects: [ProjectItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @AppStorage("tasksLayout") private var layout: Layout = .list
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString
    @State private var unscheduledOnly = false
    @State private var path: [ProjectItem] = []
    @State private var selectedTask: TaskItem?
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showSortConfig = false

    private var sortStack: SortStack { SortStack.from(sortStackJSON) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch layout {
                case .list:
                    taskList
                case .board:
                    VStack(spacing: 0) {
                        controls
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        BoardView()
                    }
                }
            }
            .background(Palette.paper)
            .navigationTitle("Tasks")
            .navigationDestination(for: ProjectItem.self) { project in
                ProjectTasksView(project: project, unscheduledOnly: $unscheduledOnly)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.fraction(0.8)])
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            LayoutSwitch(layout: $layout)
            if layout == .list {
                FilterChip(title: "Unscheduled", isOn: $unscheduledOnly)
                    .accessibilityIdentifier("tasks-filter-unscheduled")
            }
            Spacer(minLength: 0)
        }
    }

    private var taskList: some View {
        let list = TasksList(
            tasks: tasks, projects: projects,
            workspace: sessions.selectedProviderWorkspace, unscheduledOnly: unscheduledOnly
        )
        return List {
            controls
                .controlsRow()

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
    @Binding var unscheduledOnly: Bool

    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }) private var tasks: [TaskItem]
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

/// Switches Tasks between the list and the Board.
private struct LayoutSwitch: View {
    @Binding var layout: TasksView.Layout

    var body: some View {
        HStack(spacing: 2) {
            option(.list, title: "List", icon: "list.bullet")
            option(.board, title: "Board", icon: "rectangle.split.3x1")
        }
        .padding(3)
        .background(Palette.wash, in: Capsule())
    }

    private func option(_ value: TasksView.Layout, title: String, icon: String) -> some View {
        let isSelected = layout == value
        return Button {
            withAnimation(.snappy) { layout = value }
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.chip)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? Palette.onInk : Palette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(isSelected ? Palette.ink : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tasks-layout-\(value.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A chip that narrows a list while it is on.
private struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
                Text(title)
            }
            .font(.chip)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? Palette.onInk : Palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(isOn ? Palette.ink : Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
