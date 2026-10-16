import Foundation

/// The Board's three columns for one workspace: Not started, In progress, Complete.
/// Each column lists its cards nearest first, the same order as a project in the Tasks list.
/// It holds top-level tasks. Subtasks stay with their parent.
struct BoardColumns {
    struct Column: Identifiable {
        let status: TaskStatus
        let tasks: [TaskItem]

        var id: TaskStatus { status }
        var title: String { status.rawValue }
    }

    let columns: [Column]

    /// An empty `projects` or `priorities` set keeps every task. A set one keeps tasks whose
    /// project ID or priority name it holds.
    init(tasks: [TaskItem], workspace: UserSession?, projects: Set<String> = [], priorities: Set<String> = []) {
        let board = tasks.filter {
            $0.belongs(to: workspace) && !$0.isDeleted && !$0.isSubtask
                && (projects.isEmpty || projects.contains($0.project?.externalProjectID ?? ""))
                && (priorities.isEmpty || priorities.contains($0.priorityRaw ?? ""))
        }
        columns = TaskStatus.allCases.map { status in
            Column(status: status, tasks: board.filter { $0.status == status }.sorted(by: TasksList.isNearer))
        }
    }

    /// The card a drop names, resolved within this board's workspace.
    func card(withID id: String) -> TaskItem? {
        for column in columns {
            if let task = column.tasks.first(where: { $0.externalTaskID == id }) { return task }
        }
        return nil
    }
}
