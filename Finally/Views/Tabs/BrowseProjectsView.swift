import SwiftUI
import SwiftData

struct BrowseProjectsView: View {
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]
    @Query(
        filter: #Predicate<TaskItem> { $0.isDeleted == false && $0.statusRaw != "Complete" }
    )
    private var allActiveTasks: [TaskItem]
    @Environment(SyncService.self) private var syncService
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
        sortStack.sorted(allActiveTasks.filter { $0.project == nil })
    }

    private var backlogTasks: [TaskItem] {
        sortStack.sorted(allActiveTasks.filter { $0.dueDate == nil })
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
                            ForEach(inboxTasks, id: \.notionPageId) { task in
                                TaskRowView(task: task)
                                    .listRowBackground(Color(.systemGray6))
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
                            ForEach(backlogTasks, id: \.notionPageId) { task in
                                TaskRowView(task: task)
                                    .listRowBackground(Color(.systemGray6))
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
                        if projects.isEmpty {
                            Text("No projects from Notion")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(projects, id: \.notionPageId) { project in
                                NavigationLink(value: project.notionPageId) {
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
                await syncService.syncOnLaunch(modelContext: modelContext)
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
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTask: TaskItem?
    @State private var showCreator = false

    private var project: ProjectItem? {
        allProjects.first { $0.notionPageId == projectId }
    }

    private var projectTasks: [TaskItem] {
        allTasks.filter { $0.project?.notionPageId == projectId && !$0.isDeleted }
    }

    var body: some View {
        List {
            ForEach(projectTasks, id: \.notionPageId) { task in
                TaskRowView(task: task)
                    .listRowBackground(Color(.systemGray6))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedTask = task }
            }
        }
        .navigationTitle(project?.title ?? "Project")
        .refreshable {
            await syncService.syncOnLaunch(modelContext: modelContext)
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
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showCreator {
                Button { showCreator = true } label: {
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
