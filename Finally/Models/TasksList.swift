import Foundation

/// The Tasks tab's list for one workspace: the Inbox first, then each project.
/// It holds open top-level tasks. Subtasks stay with their parent.
struct TasksList {
    /// How many tasks each project shows before its "+N more" row.
    static let projectLimit = 3

    /// One project and its open tasks, nearest first.
    struct ProjectGroup: Identifiable {
        let project: ProjectItem
        let tasks: [TaskItem]

        var id: String { project.externalProjectID }
        var nearest: [TaskItem] { Array(tasks.prefix(TasksList.projectLimit)) }
        var moreCount: Int { tasks.count - nearest.count }
    }

    let inbox: [TaskItem]
    let projects: [ProjectGroup]

    /// `unscheduledOnly` narrows the list to Unscheduled tasks, those with neither a scheduled
    /// day nor a deadline, and drops projects left with none.
    init(tasks: [TaskItem], projects: [ProjectItem], workspace: UserSession?, unscheduledOnly: Bool = false) {
        let open = tasks.filter {
            $0.belongs(to: workspace) && !$0.isDeleted && $0.status != .done && !$0.isSubtask
                && (!unscheduledOnly || ($0.scheduledDay == nil && $0.deadline == nil))
        }
        inbox = open.filter { $0.project == nil }
        let byProject = Dictionary(grouping: open.filter { $0.project != nil }) { $0.project!.externalProjectID }
        self.projects = projects
            .scoped(to: workspace)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            .map { project in
                ProjectGroup(
                    project: project,
                    tasks: (byProject[project.externalProjectID] ?? []).sorted(by: Self.isNearer)
                )
            }
            .filter { !unscheduledOnly || !$0.tasks.isEmpty }
    }

    /// Earlier deadline first, then earlier scheduled day. A missing date sorts last.
    static func isNearer(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.deadline != b.deadline { return a.deadline ?? .distantFuture < b.deadline ?? .distantFuture }
        if a.scheduledDay != b.scheduledDay { return a.scheduledDay ?? .distantFuture < b.scheduledDay ?? .distantFuture }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }
}
