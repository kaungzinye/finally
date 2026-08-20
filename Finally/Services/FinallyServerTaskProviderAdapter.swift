import Foundation
import SwiftData

final class FinallyServerTaskProviderAdapter: TaskProviderAdapter {
    typealias WorkspaceState = UserSession
    typealias TaskState = TaskItem
    typealias LocalStore = ModelContext

    let providerIdentity: TaskProviderIdentity = .finallyServer
    let capabilities: Set<TaskProviderCapability> = [
        .createTasks,
        .readTasks,
        .updateTasks,
        .completeTasks,
        .deleteTasks,
    ]

    private let api: FinallyServerAPIClient

    init(api: FinallyServerAPIClient) {
        self.api = api
    }

    func workspaceIdentity(for workspace: UserSession) -> ProviderWorkspaceIdentity {
        ProviderWorkspaceIdentity(provider: providerIdentity, externalID: workspace.workspaceId)
    }

    func taskIdentity(for task: TaskItem, in workspace: ProviderWorkspaceIdentity) -> ProviderTaskIdentity {
        ProviderTaskIdentity(workspace: workspace, externalID: task.externalTaskID)
    }

    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession?,
        store: ModelContext
    ) async throws {
        guard let workspace else { throw TaskProviderAdapterError.workspaceRequired }
        guard workspace.providerIdentity == .finallyServer,
              let projectID = workspace.serverProjectID else {
            throw FinallyServerClientError.invalidResponse
        }

        switch intent {
        case .push:
            try await pushChanges(workspaceID: workspace.workspaceId, projectID: projectID, store: store)
        case .launch, .incremental:
            try await pushChanges(workspaceID: workspace.workspaceId, projectID: projectID, store: store)
            try await pullKnownTasks(workspaceID: workspace.workspaceId, store: store)
        case .full:
            try await pullKnownTasks(workspaceID: workspace.workspaceId, store: store)
        }
    }

    private func pushChanges(workspaceID: String, projectID: Int64, store: ModelContext) async throws {
        let tasks = try store.fetch(FetchDescriptor<TaskItem>()).filter {
            $0.providerWorkspaceId == workspaceID && $0.isDirty
        }

        for task in tasks {
            if task.isDeleted {
                if task.lastSyncedAt != nil {
                    try await api.deleteTask(id: task.externalTaskID)
                }
                store.delete(task)
                try store.save()
                continue
            }

            let remote: FinallyServerTask
            if task.lastSyncedAt == nil {
                let created = try await api.createTask(projectID: projectID, title: task.title)
                task.externalTaskID = created.id
                task.lastSyncedAt = Date()
                try store.save()
                if task.status == .done {
                    remote = try await api.completeTask(id: created.id)
                } else {
                    remote = created
                }
            } else if task.status == .done {
                _ = try await api.updateTask(
                    id: task.externalTaskID,
                    title: task.title,
                    isCompleted: false
                )
                remote = try await api.completeTask(id: task.externalTaskID)
            } else {
                remote = try await api.updateTask(
                    id: task.externalTaskID,
                    title: task.title,
                    isCompleted: false
                )
            }
            apply(remote, to: task)
            task.isDirty = false
            task.lastSyncedAt = Date()
            try store.save()
        }
    }

    private func pullKnownTasks(workspaceID: String, store: ModelContext) async throws {
        let tasks = try store.fetch(FetchDescriptor<TaskItem>()).filter {
            $0.providerWorkspaceId == workspaceID && $0.lastSyncedAt != nil && !$0.isDirty && !$0.isDeleted
        }
        for task in tasks {
            let remote = try await api.readTask(id: task.externalTaskID)
            apply(remote, to: task)
            task.lastSyncedAt = Date()
        }
        try store.save()
    }

    private func apply(_ remote: FinallyServerTask, to task: TaskItem) {
        task.title = remote.title
        task.status = remote.isCompleted ? .done : .notStarted
    }
}
