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
        .scheduledDay: .lossy(
            reason: "Finally Server carries scheduled days as timestamps, so a remotely edited scheduled day arrives timed."
        ),
        .deadline: .lossless,
        .state: .lossy(
            reason: "Finally Server records completion only, so In progress stays on this device."
        ),
        .project: .lossy(
            reason: "A Finally Server workspace is one server project, so the project follows the workspace."
        ),
        .labels: .unsupported(reason: "Finally Server does not expose labels."),
        .priority: .lossless,
        .subtasks: .unsupported(reason: "Finally Server does not expose parent relationships."),
        .recurrence: .unsupported(reason: "Finally Server does not expose recurrence."),
        .reminders: .lossless,
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
            if task.serverTaskMissing { throw FinallyServerClientError.notFound }
            if task.serverConflictJSON != nil {
                do {
                    let current = try await api.readTask(id: task.externalTaskID)
                    storeConflict(current, fields: task.serverConflictFields, task: task)
                    try store.save()
                    throw FinallyServerClientError.conflict(current: current, fields: task.serverConflictFields)
                } catch FinallyServerClientError.notFound {
                    task.serverTaskMissing = true
                    try store.save()
                    throw FinallyServerClientError.notFound
                }
            }
            if task.isDeleted {
                if task.lastSyncedAt != nil {
                    do { try await api.deleteTask(id: task.externalTaskID, revision: task.serverRevision) }
                    catch FinallyServerClientError.notFound {
                        store.delete(task)
                        try store.save()
                        continue
                    }
                    catch FinallyServerClientError.conflict(let current, let fields) {
                        storeConflict(current, fields: fields, task: task)
                        try store.save()
                        throw FinallyServerClientError.conflict(current: current, fields: fields)
                    }
                }
                store.delete(task)
                try store.save()
                continue
            }
            let outgoingStatus = task.status
            let outgoing = task.serverMutation
            var mutation = outgoing
            mutation.baseRevision = task.serverRevision
            if let baseline = task.acceptedServerMutation {
                mutation.changedFields = outgoing.differences(from: baseline)
            } else if task.lastSyncedAt != nil {
                throw FinallyServerClientError.invalidResponse
            }
            if mutation.changedFields?.isEmpty == true {
                task.isDirty = false
                try store.save()
                continue
            }
            do {
                let remote: FinallyServerTask
                if task.lastSyncedAt == nil {
                    remote = try await api.createTask(projectID: projectID, mutation: mutation)
                    task.externalTaskID = remote.id
                } else {
                    remote = try await api.updateTask(id: task.externalTaskID, mutation: mutation)
                }
                let editsDuringPush = task.serverMutation
                let statusDuringPush = task.status
                try apply(remote, to: task, workspaceID: workspaceID, store: store)
                let acknowledged = task.serverMutation
                task.applyServerMutation(editsDuringPush, fields: editsDuringPush.differences(from: outgoing))
                if statusDuringPush != outgoingStatus { task.status = statusDuringPush }
                task.isDirty = !task.serverMutation.differences(from: acknowledged).isEmpty || task.isDeleted
                task.lastSyncedAt = Date()
                try store.save()
            } catch FinallyServerClientError.notFound {
                task.serverTaskMissing = true
                try store.save()
                throw FinallyServerClientError.notFound
            } catch FinallyServerClientError.conflict(let current, let fields) {
                storeConflict(current, fields: fields, task: task)
                try store.save()
                throw FinallyServerClientError.conflict(current: current, fields: fields)
            }
        }
    }

    private func storeConflict(_ current: FinallyServerTask, fields: [String], task: TaskItem) {
        task.serverConflictJSON = current.mutation.json
        task.serverConflictFields = fields
        task.serverRevision = current.revision
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
        // A scheduled day is date-only, so the server's timestamp reads as its calendar day.
        task.scheduledDay = remote.scheduledDay.map { Calendar.current.startOfDay(for: $0) }
        task.deadline = remote.deadline
        task.deadlineHasTime = remote.deadlineHasTime
        task.taskReminders = remote.reminders
        task.priority = remote.priority
        task.serverRevision = remote.revision
        task.serverSnapshotJSON = task.serverMutation.json
        task.serverConflictJSON = nil
        task.serverConflictFields = []
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

}
