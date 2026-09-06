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
    @State private var selectedTask: TaskItem?
    @AppStorage("sortStack") private var sortStackJSON: String = SortStack.default.jsonString

    private var sortStack: SortStack {
        SortStack.from(sortStackJSON)
    }

    private var inboxTasks: [TaskItem] {
        sortStack.sorted(selectedTasks.filter { $0.project == nil })
    }

    private var backlogTasks: [TaskItem] {
        sortStack.sorted(selectedTasks.filter { $0.dueDate == nil })
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
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(inboxTasks, id: \.externalTaskID) { task in
                                TaskRowView(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTask = task }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Inbox", icon: "tray")
                }

                // Backlog section — tasks without a due date
                Section {
                    if expandedSections.contains("Backlog") {
                        if backlogTasks.isEmpty {
                            Text("No undated tasks")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(backlogTasks, id: \.externalTaskID) { task in
                                TaskRowView(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTask = task }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Backlog", icon: "clock")
                }

                // Projects section — collapsible list of projects
                Section {
                    if expandedSections.contains("Projects") {
                        if selectedProjects.isEmpty {
                            Text("No projects")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(selectedProjects, id: \.externalProjectID) { project in
                                NavigationLink(value: project.externalProjectID) {
                                    HStack {
                                        if let emoji = project.iconEmoji {
                                            Text(emoji)
                                                .font(.body)
                                        } else {
                                            Image(systemName: "folder")
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(project.title)
                                        Spacer()
                                        Text("\(project.tasks.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Projects", icon: "folder")
                }
            }
            .listStyle(.plain)
            .navigationTitle("Browse")
            .navigationDestination(for: String.self) { projectId in
                ProjectDetailView(projectId: projectId)
            }
            .toolbar {
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

    private func collapsibleHeader(_ title: String, icon: String) -> some View {
        Button {
            withAnimation {
                if expandedSections.contains(title) {
                    expandedSections.remove(title)
                } else {
                    expandedSections.insert(title)
                }
            }
        } label: {
            HStack {
                Image(systemName: expandedSections.contains(title) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
            }
            .foregroundStyle(.primary)
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
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var showCreator = false

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
        .listStyle(.plain)
        .navigationTitle(project?.title ?? "Project")
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
        .safeAreaInset(edge: .bottom) {
            if showCreator {
                InlineTaskCreator(presetProject: project)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showCreator {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCreator = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 52, height: 52)
                        .background(Color.primary)
                        .clipShape(Circle())
                }
                .padding(20)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
    }
}
