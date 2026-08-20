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
    static let canonicalFieldSupport: [CanonicalTaskField: TaskProviderFieldSupport] = [
        .title: .lossless,
        .plannedDay: .lossy(reason: "Finally Server stores planned days as timestamps."),
        .deadline: .lossy(reason: "Finally Server stores deadlines as timestamps."),
        .state: .lossless,
        .project: .lossless,
        .labels: .unsupported(reason: "Finally Server does not expose labels."),
        .priority: .lossless,
        .estimate: .unsupported(reason: "Finally Server does not expose estimates."),
        .subtasks: .unsupported(reason: "Finally Server does not expose parent relationships."),
        .recurrence: .unsupported(reason: "Finally Server does not expose recurrence."),
        .reminders: .unsupported(reason: "Finally Server does not expose reminders."),
        .externalReferences: .unsupported(reason: "Finally Server does not expose external references."),
    ]
    let fieldSupport = canonicalFieldSupport

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
            let mutation = FinallyServerTaskMutation(
                title: task.title,
                isCompleted: false,
                plannedDay: task.targetDate,
                deadline: task.dueDate,
                priority: task.priority
            )
            if task.lastSyncedAt == nil {
                let created = try await api.createTask(projectID: projectID, mutation: mutation)
                task.externalTaskID = created.id
                task.lastSyncedAt = Date()
                try store.save()
                if task.status == .done {
                    remote = try await api.completeTask(id: created.id)
                } else {
                    remote = created
                }
            } else if task.status == .done {
                _ = try await api.updateTask(id: task.externalTaskID, mutation: mutation)
                remote = try await api.completeTask(id: task.externalTaskID)
            } else {
                remote = try await api.updateTask(id: task.externalTaskID, mutation: mutation)
            }
            try apply(
                remote,
                to: task,
                workspaceID: workspaceID,
                preserveDateSemantics: true,
                store: store
            )
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
            try apply(
                remote,
                to: task,
                workspaceID: workspaceID,
                preserveDateSemantics: false,
                store: store
            )
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
        preserveDateSemantics: Bool,
        store: ModelContext
    ) throws {
        task.title = remote.title
        task.status = remote.isCompleted ? .done : .notStarted
        task.targetDate = remote.plannedDay
        task.dueDate = remote.deadline
        if !preserveDateSemantics {
            task.targetDateHasTime = remote.plannedDay != nil
            task.dueDateHasTime = remote.deadline != nil
        }
        task.priority = remote.priority
        let remoteProjectID = String(remote.projectID)
        let descriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate<ProjectItem> { project in
            project.externalProjectID == remoteProjectID && project.providerWorkspaceId == workspaceID
        })
        task.project = try store.fetch(descriptor).first
    }
}
