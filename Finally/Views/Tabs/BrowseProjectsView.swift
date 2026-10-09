import SwiftUI
import SwiftData

struct BrowseProjectsView: View {
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]
    @Query(
        filter: #Predicate<TaskItem> { $0.isDeleted == false && $0.statusRaw != "Complete" }
    )
    private var allActiveTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(\.modelContext) private var modelContext

    @State private var expandedSections: Set<String> = ["Inbox", "Projects"]
    @State private var showSearch = false
    @State private var showSortConfig = false
    @State private var showSettings = false
    @State private var selectedTask: TaskItem?
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString

    private var sortStack: SortStack {
        SortStack.from(sortStackJSON)
    }

    private var inboxTasks: [TaskItem] {
        sortStack.sorted(selectedTasks.filter { $0.project == nil })
    }

    private var backlogTasks: [TaskItem] {
        sortStack.sorted(selectedTasks.filter { $0.deadline == nil })
    }

    private var selectedWorkspace: UserSession? { sessions.selectedProviderWorkspace }

    private var selectedTasks: [TaskItem] {
        allActiveTasks.scoped(to: selectedWorkspace)
    }

    private var selectedProjects: [ProjectItem] {
        projects.scoped(to: selectedWorkspace)
    }

    var body: some View {
        NavigationStack {
            List {
                // Inbox section — tasks without a project
                Section {
                    if expandedSections.contains("Inbox") {
                        if inboxTasks.isEmpty {
                            Text("No unassigned tasks")
                                .foregroundStyle(Palette.muted)
                                .font(.meta)
                                .cardRow()
                        } else {
                            ForEach(inboxTasks, id: \.externalTaskID) { task in
                                TaskRowView(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTask = task }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Inbox")
                }

                // Backlog section — tasks without a deadline
                Section {
                    if expandedSections.contains("Backlog") {
                        if backlogTasks.isEmpty {
                            Text("No undated tasks")
                                .foregroundStyle(Palette.muted)
                                .font(.meta)
                                .cardRow()
                        } else {
                            ForEach(backlogTasks, id: \.externalTaskID) { task in
                                TaskRowView(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTask = task }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Backlog")
                }

                // Projects section — collapsible list of projects
                Section {
                    if expandedSections.contains("Projects") {
                        if selectedProjects.isEmpty {
                            Text("No projects")
                                .foregroundStyle(Palette.muted)
                                .font(.meta)
                                .cardRow()
                        } else {
                            ForEach(selectedProjects, id: \.externalProjectID) { project in
                                NavigationLink(value: project.externalProjectID) {
                                    HStack {
                                        if let emoji = project.iconEmoji {
                                            Text(emoji)
                                                .font(.body)
                                        } else {
                                            Image(systemName: "folder")
                                                .foregroundStyle(Palette.muted)
                                        }
                                        Text(project.title)
                                            .foregroundStyle(Palette.ink)
                                        Spacer()
                                        Text("\(project.tasks.count)")
                                            .font(.meta)
                                            .foregroundStyle(Palette.muted)
                                    }
                                }
                                .cardRow()
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Projects")
                }
            }
            .paperList()
            .navigationTitle("Browse")
            .navigationDestination(for: String.self) { projectId in
                ProjectDetailView(projectId: projectId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showSortConfig = true } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }

                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
            .refreshable {
                try? await taskProvider.synchronize(.launch, store: modelContext)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.fraction(0.8)])
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
        }
    }

    private func collapsibleHeader(_ title: String) -> some View {
        Button {
            withAnimation {
                if expandedSections.contains(title) {
                    expandedSections.remove(title)
                } else {
                    expandedSections.insert(title)
                }
            }
        } label: {
            SectionLabel(title: title) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(expandedSections.contains(title) ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project Detail View

struct ProjectDetailView: View {
    let projectId: String

    @Query private var allTasks: [TaskItem]
    @Query private var allProjects: [ProjectItem]
    @Query private var sessions: [UserSession]
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(NavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?

    private var project: ProjectItem? {
        allProjects.scoped(to: sessions.selectedProviderWorkspace).first { $0.externalProjectID == projectId }
    }

    private var projectTasks: [TaskItem] {
        allTasks.scoped(to: sessions.selectedProviderWorkspace).filter {
            $0.project?.externalProjectID == projectId && !$0.isDeleted
        }
    }

    var body: some View {
        List {
            ForEach(projectTasks, id: \.externalTaskID) { task in
                TaskRowView(task: task)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedTask = task }
            }
        }
        .paperList()
        .navigationTitle(project?.title ?? "Project")
        .onAppear { router.creatorProject = project }
        .onDisappear { router.creatorProject = nil }
        .refreshable {
            try? await taskProvider.synchronize(.launch, store: modelContext)
        }
        .overlay {
            if projectTasks.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "checkmark.circle",
                    description: Text("No tasks in this project")
                )
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.fraction(0.8)])
        }
    }
}
