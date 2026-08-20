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
            try await pullTasks(workspaceID: workspace.workspaceId, projectID: projectID, store: store)
        case .full:
            try await pullTasks(workspaceID: workspace.workspaceId, projectID: projectID, store: store)
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
            try apply(remote, to: task, workspaceID: workspaceID, store: store)
            task.isDirty = false
            task.lastSyncedAt = Date()
            try store.save()
        }
    }

    private func pullTasks(workspaceID: String, projectID: Int64, store: ModelContext) async throws {
        let localTasks = try store.fetch(FetchDescriptor<TaskItem>()).filter {
            $0.providerWorkspaceId == workspaceID
        }
        var tasksByExternalID: [String: TaskItem] = [:]
        for task in localTasks {
            guard tasksByExternalID.updateValue(task, forKey: task.externalTaskID) == nil else {
                throw FinallyServerClientError.duplicateLocalTaskIdentity(task.externalTaskID)
            }
        }
        let remoteTasks = try await api.listTasks(projectID: projectID)
        let remoteTaskIDs = Set(remoteTasks.map(\.id))
        for remote in remoteTasks {
            let task: TaskItem
            if let existing = tasksByExternalID[remote.id] {
                guard !existing.isDirty, !existing.isDeleted else { continue }
                task = existing
            } else {
                task = TaskItem(externalTaskID: remote.id, title: remote.title)
                task.providerWorkspaceId = workspaceID
                store.insert(task)
            }
            try apply(remote, to: task, workspaceID: workspaceID, store: store)
            task.lastSyncedAt = Date()
        }
        for task in localTasks where
            task.lastSyncedAt != nil &&
            !task.isDirty &&
            !task.isDeleted &&
            !remoteTaskIDs.contains(task.externalTaskID) {
            store.delete(task)
        }
        try store.save()
    }

    private func apply(
        _ remote: FinallyServerTask,
        to task: TaskItem,
        workspaceID: String,
        store: ModelContext
    ) throws {
        task.title = remote.title
        task.status = remote.isCompleted ? .done : .notStarted
        let remoteProjectID = String(remote.projectID)
        let descriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate<ProjectItem> { project in
            project.externalProjectID == remoteProjectID && project.providerWorkspaceId == workspaceID
        })
        task.project = try store.fetch(descriptor).first
    }
}
