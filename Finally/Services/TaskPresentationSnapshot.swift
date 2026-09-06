import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

struct TaskPresentationSummary: Codable, Equatable, Identifiable, Sendable {
    let providerWorkspaceID: String
    let externalTaskID: String
    let title: String
    let dueDate: Date?
    let priorityRaw: String?
    let isComplete: Bool

    var id: String { "\(providerWorkspaceID):\(externalTaskID)" }
}

enum TaskPresentationQuery {
    static func summaries(
        from tasks: some Sequence<TaskItem>,
        workspace: UserSession?
    ) -> [TaskPresentationSummary] {
        tasks
            .filter { task in
                task.belongs(to: workspace) && !task.isDeleted && !task.isSubtask
            }
            .sorted { lhs, rhs in
                if let left = lhs.dueDate, let right = rhs.dueDate { return left < right }
                if lhs.dueDate != nil { return true }
                if rhs.dueDate != nil { return false }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { task in
                TaskPresentationSummary(
                    providerWorkspaceID: task.providerWorkspaceId ?? workspace?.workspaceId ?? "unassigned",
                    externalTaskID: task.externalTaskID,
                    title: task.title,
                    dueDate: task.dueDate,
                    priorityRaw: task.priorityRaw,
                    isComplete: task.status == .done
                )
            }
    }
}

enum WidgetTaskSnapshotStore {
    static let storageKey = "taskPresentationSummaries"

    static func publish(store: ModelContext) throws {
        let tasks = try store.fetch(FetchDescriptor<TaskItem>())
        let workspace = try store.selectedProviderWorkspace()
        let summaries = TaskPresentationQuery.summaries(from: tasks, workspace: workspace)
        let data = try JSONEncoder().encode(summaries)
        UserDefaults(suiteName: AppConstants.appGroupID)?.set(data, forKey: storageKey)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
#endif
    }
}
