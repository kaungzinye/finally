import SwiftUI
import SwiftData

struct BrowseProjectsView: View {
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects, id: \.notionPageId) { project in
                    NavigationLink(value: project.notionPageId) {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(project.title)
                            Spacer()
                            Text("\(project.tasks.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: String.self) { projectId in
                ProjectDetailView(projectId: projectId)
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No projects",
                        systemImage: "folder",
                        description: Text("Projects from Notion will appear here")
                    )
                }
            }
        }
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
