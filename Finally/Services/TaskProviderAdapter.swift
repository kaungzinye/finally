import Foundation
import Observation
import SwiftData

struct TaskProviderIdentity: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ProviderWorkspaceIdentity: Codable, Hashable, Sendable {
    let provider: TaskProviderIdentity
    let externalID: String
}

struct ProviderTaskIdentity: Codable, Hashable, Sendable {
    let workspace: ProviderWorkspaceIdentity
    let externalID: String
}

enum TaskProviderCapability: String, Codable, Hashable, Sendable {
    case createTasks
    case readTasks
    case updateTasks
    case completeTasks
    case deleteTasks
    case projects
    case labels
    case subtasks
    case recurrence
}

enum TaskProviderSyncIntent: Sendable {
    case launch
    case incremental
    case full
    case push
}

enum TaskProviderAdapterError: Error {
    case workspaceRequired
}

protocol TaskProviderAdapter: AnyObject {
    associatedtype WorkspaceState
    associatedtype TaskState
    associatedtype LocalStore

    var providerIdentity: TaskProviderIdentity { get }
    var capabilities: Set<TaskProviderCapability> { get }

    func workspaceIdentity(for workspace: WorkspaceState) -> ProviderWorkspaceIdentity
    func taskIdentity(for task: TaskState, in workspace: ProviderWorkspaceIdentity) -> ProviderTaskIdentity
    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: WorkspaceState?,
        store: LocalStore
    ) async throws
}

extension SyncService: TaskProviderAdapter {
    typealias WorkspaceState = UserSession
    typealias TaskState = TaskItem
    typealias LocalStore = ModelContext

    var providerIdentity: TaskProviderIdentity {
        TaskProviderIdentity(rawValue: "notion")
    }

    var capabilities: Set<TaskProviderCapability> {
        [
            .createTasks,
            .readTasks,
            .updateTasks,
            .completeTasks,
            .deleteTasks,
            .projects,
            .labels,
            .subtasks,
            .recurrence,
        ]
    }

    func workspaceIdentity(for workspace: UserSession) -> ProviderWorkspaceIdentity {
        ProviderWorkspaceIdentity(provider: providerIdentity, externalID: workspace.workspaceId)
    }

    func taskIdentity(for task: TaskItem, in workspace: ProviderWorkspaceIdentity) -> ProviderTaskIdentity {
        ProviderTaskIdentity(workspace: workspace, externalID: task.notionPageId)
    }

    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession?,
        store: ModelContext
    ) async throws {
        switch intent {
        case .launch:
            await syncOnLaunch(modelContext: store)
        case .incremental:
            guard let workspace else { throw TaskProviderAdapterError.workspaceRequired }
            try await incrementalSync(session: workspace, modelContext: store)
        case .full:
            guard let workspace else { throw TaskProviderAdapterError.workspaceRequired }
            try await fullSync(session: workspace, modelContext: store)
        case .push:
            guard let workspace else { throw TaskProviderAdapterError.workspaceRequired }
            try await pushDirtyChanges(session: workspace, modelContext: store)
        }
    }
}

@Observable
final class TaskProviderCoordinator {
    let providerIdentity: TaskProviderIdentity
    let capabilities: Set<TaskProviderCapability>
    private let synchronizeProvider: (TaskProviderSyncIntent, UserSession?, ModelContext) async throws -> Void

    var isSyncing = false

    init<Adapter: TaskProviderAdapter>(adapter: Adapter)
    where Adapter.WorkspaceState == UserSession, Adapter.LocalStore == ModelContext {
        providerIdentity = adapter.providerIdentity
        capabilities = adapter.capabilities
        synchronizeProvider = { intent, workspace, store in
            try await adapter.synchronize(intent, workspace: workspace, store: store)
        }
    }

    convenience init() {
        self.init(adapter: SyncService())
    }

    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession? = nil,
        store: ModelContext
    ) async throws {
        isSyncing = true
        defer { isSyncing = false }
        try await synchronizeProvider(intent, workspace, store)
    }
}
