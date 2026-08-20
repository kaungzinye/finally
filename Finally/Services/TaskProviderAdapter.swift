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

enum TaskProviderSyncIntent: Hashable, Sendable {
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
    private struct SynchronizationKey: Hashable {
        let intent: TaskProviderSyncIntent
        let workspaceID: String
    }

    let providerIdentity: TaskProviderIdentity
    let capabilities: Set<TaskProviderCapability>
    private let synchronizeProvider: ((TaskProviderSyncIntent, UserSession?, ModelContext) async throws -> Void)?
    private let notionAdapter: SyncService
    private let credentials: FinallyServerCredentialStore
    @ObservationIgnored private var activeSynchronizations: [SynchronizationKey: Task<Void, Error>] = [:]

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

    @MainActor
    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession? = nil,
        store: ModelContext
    ) async throws {
        let selectedWorkspace: UserSession?
        if let workspace {
            selectedWorkspace = workspace
        } else if intent == .launch {
            selectedWorkspace = nil
        } else {
            selectedWorkspace = try store.selectedProviderWorkspace()
        }
        if intent != .launch, selectedWorkspace == nil {
            throw TaskProviderAdapterError.workspaceRequired
        }

        let key = SynchronizationKey(
            intent: intent,
            workspaceID: selectedWorkspace?.workspaceId ?? "launch"
        )
        if let activeSynchronization = activeSynchronizations[key] {
            try await activeSynchronization.value
            return
        }

        let synchronization = Task { [self] in
            try await performSynchronization(intent, workspace: selectedWorkspace, store: store)
        }
        activeSynchronizations[key] = synchronization
        isSyncing = true
        lastError = nil
        defer {
            activeSynchronizations.removeValue(forKey: key)
            isSyncing = !activeSynchronizations.isEmpty
        }
        do {
            try await synchronization.value
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    @MainActor
    func submitPendingChanges(for tasks: [TaskItem], store: ModelContext) async throws {
        do {
            try persistPendingChanges(store: store)

            let sessions = try store.fetch(FetchDescriptor<UserSession>())
            let selectedWorkspaceID = sessions.selectedProviderWorkspace?.workspaceId
            let workspaceIDs = Set(try tasks.map { task in
                if let workspaceID = task.providerWorkspaceId { return workspaceID }
                guard let selectedWorkspaceID else {
                    throw TaskProviderAdapterError.workspaceRequired
                }
                return selectedWorkspaceID
            })
            let workspaces: [UserSession]
            if workspaceIDs.isEmpty {
                guard let selected = sessions.selectedProviderWorkspace else {
                    throw TaskProviderAdapterError.workspaceRequired
                }
                workspaces = [selected]
            } else {
                workspaces = sessions.filter { workspaceIDs.contains($0.workspaceId) }
                guard workspaces.count == workspaceIDs.count else {
                    throw TaskProviderAdapterError.workspaceRequired
                }
            }

            for workspace in workspaces {
                try await synchronize(.push, workspace: workspace, store: store)
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    @MainActor
    func submitPendingChangesReportingFailure(for tasks: [TaskItem], store: ModelContext) async {
        try? await submitPendingChanges(for: tasks, store: store)
    }

    @MainActor
    func retryPendingChanges(store: ModelContext) async {
        do {
            let tasks = try store.fetch(FetchDescriptor<TaskItem>()).filter { $0.isDirty }
            guard !tasks.isEmpty else {
                lastError = nil
                return
            }
            try await submitPendingChanges(for: tasks, store: store)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func performSynchronization(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession?,
        store: ModelContext
    ) async throws {
        if let synchronizeProvider {
            try await synchronizeProvider(intent, workspace, store)
            return
        }
        guard let workspace else {
            try await notionAdapter.synchronize(intent, workspace: nil, store: store)
            return
        }
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
    }

    func persistPendingChanges(store: ModelContext) throws {
        try store.save()
    }

    func clearError() {
        lastError = nil
    }
}
