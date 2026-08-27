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
        .plannedDay: .lossy(
            reason: "Finally Server carries planned days as timestamps, so a remotely edited planned day arrives timed."
        ),
        .deadline: .lossy(
            reason: "Finally Server carries deadlines as timestamps, so a remotely edited deadline arrives timed."
        ),
        .state: .lossy(
            reason: "Finally Server records completion only, so In progress stays on this device."
        ),
        .project: .lossy(
            reason: "A Finally Server workspace is one server project, so the project follows the workspace."
        ),
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
                store: store
            )
            task.lastSyncedAt = Date()
        }
        // A Finally Server provider workspace is exactly one server project. A synced task the
        // project no longer lists has left this workspace, whether it was deleted on the server
        // or moved to another project, and Finally never copies tasks across workspaces. Either
        // way the local record goes. Local-only drafts and dirty edits are held back above.
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
        task.status = canonicalStatus(remoteIsCompleted: remote.isCompleted, local: task.status)
        // Finally Server carries every date as a timestamp, so a payload cannot say whether the
        // user meant a whole day or a moment. Keep the local reading while the instant is
        // unchanged, and read a genuinely new instant as timed.
        if !isSameInstant(task.targetDate, remote.plannedDay) {
            task.targetDate = remote.plannedDay
            task.targetDateHasTime = remote.plannedDay != nil
        }
        if !isSameInstant(task.dueDate, remote.deadline) {
            task.dueDate = remote.deadline
            task.dueDateHasTime = remote.deadline != nil
        }
        task.priority = remote.priority
        let remoteProjectID = String(remote.projectID)
        let descriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate<ProjectItem> { project in
            project.externalProjectID == remoteProjectID && project.providerWorkspaceId == workspaceID
        })
        task.project = try store.fetch(descriptor).first
    }

    /// Finally Server records completion only. A task the user marked In progress stays In
    /// progress while the server reports it unfinished.
    private func canonicalStatus(remoteIsCompleted: Bool, local: TaskStatus) -> TaskStatus {
        guard !remoteIsCompleted else { return .done }
        return local == .done ? .notStarted : local
    }

    /// The wire format carries whole seconds, so a value that survived a round trip can come
    /// back with its fractional part trimmed.
    private func isSameInstant(_ local: Date?, _ remote: Date?) -> Bool {
        switch (local, remote) {
        case (nil, nil):
            return true
        case let (local?, remote?):
            return abs(local.timeIntervalSince(remote)) < 1
        default:
            return false
        }
    }
}
