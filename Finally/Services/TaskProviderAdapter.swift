import Foundation
import Observation
import SwiftData

struct TaskProviderIdentity: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension TaskProviderIdentity {
    static let notion = TaskProviderIdentity(rawValue: "notion")
    static let finallyServer = TaskProviderIdentity(rawValue: "finally-server")
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
        .notion
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
        ProviderTaskIdentity(workspace: workspace, externalID: task.externalTaskID)
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
    private let synchronizeProvider: ((TaskProviderSyncIntent, UserSession?, ModelContext) async throws -> Void)?
    private let notionAdapter: SyncService
    private let credentials: FinallyServerCredentialStore

    var isSyncing = false
    var lastError: String?

    init<Adapter: TaskProviderAdapter>(adapter: Adapter)
    where Adapter.WorkspaceState == UserSession, Adapter.LocalStore == ModelContext {
        providerIdentity = adapter.providerIdentity
        capabilities = adapter.capabilities
        notionAdapter = SyncService()
        credentials = KeychainFinallyServerCredentialStore()
        synchronizeProvider = { intent, workspace, store in
            try await adapter.synchronize(intent, workspace: workspace, store: store)
        }
    }

    init(
        notionAdapter: SyncService = SyncService(),
        credentials: FinallyServerCredentialStore = KeychainFinallyServerCredentialStore()
    ) {
        providerIdentity = .notion
        capabilities = notionAdapter.capabilities
        self.notionAdapter = notionAdapter
        self.credentials = credentials
        synchronizeProvider = nil
    }

    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession? = nil,
        store: ModelContext
    ) async throws {
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            if let synchronizeProvider {
                try await synchronizeProvider(intent, workspace, store)
                return
            }
            let selectedWorkspace: UserSession?
            if let workspace {
                selectedWorkspace = workspace
            } else {
                selectedWorkspace = try store.selectedProviderWorkspace()
            }
            guard let workspace = selectedWorkspace else { throw TaskProviderAdapterError.workspaceRequired }
            switch workspace.providerIdentity {
            case .notion:
                try await notionAdapter.synchronize(intent, workspace: workspace, store: store)
            case .finallyServer:
                guard let urlString = workspace.serverBaseURL,
                      let baseURL = URL(string: urlString),
                      let token = credentials.token(workspaceID: workspace.workspaceId) else {
                    throw FinallyServerClientError.unauthorized
                }
                let api = URLSessionFinallyServerAPIClient(baseURL: baseURL, token: token)
                try await FinallyServerTaskProviderAdapter(api: api)
                    .synchronize(intent, workspace: workspace, store: store)
            default:
                throw FinallyServerClientError.invalidResponse
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func persistPendingChanges(store: ModelContext) throws {
        try store.save()
    }

    func clearError() {
        lastError = nil
    }
}
