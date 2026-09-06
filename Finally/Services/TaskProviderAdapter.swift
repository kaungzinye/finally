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

enum CanonicalTaskField: String, Codable, CaseIterable, Hashable, Sendable {
    case title
    case plannedDay
    case deadline
    case state
    case project
    case labels
    case priority
    case estimate
    case subtasks
    case recurrence
    case reminders
    case externalReferences
}

enum TaskProviderFieldSupport: Codable, Equatable, Sendable {
    case lossless
    case lossy(reason: String)
    case unsupported(reason: String)
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
    var fieldSupport: [CanonicalTaskField: TaskProviderFieldSupport] { get }

    func workspaceIdentity(for workspace: WorkspaceState) -> ProviderWorkspaceIdentity
    func taskIdentity(for task: TaskState, in workspace: ProviderWorkspaceIdentity) -> ProviderTaskIdentity
    func synchronize(
        _ intent: TaskProviderSyncIntent,
        workspace: WorkspaceState?,
        store: LocalStore
    ) async throws
}

extension TaskProviderAdapter {
    var fieldSupport: [CanonicalTaskField: TaskProviderFieldSupport] {
        Dictionary(uniqueKeysWithValues: CanonicalTaskField.allCases.map { field in
            (field, .unsupported(reason: "The adapter does not declare support for this field."))
        })
    }
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

    var fieldSupport: [CanonicalTaskField: TaskProviderFieldSupport] {
        [
            .title: .lossless,
            .plannedDay: .lossy(
                reason: "A separate Notion planned-day property is required to preserve every planned-day shape."
            ),
            .deadline: .lossless,
            .state: .lossless,
            .project: .lossless,
            .labels: .lossless,
            .priority: .lossless,
            .estimate: .unsupported(reason: "No estimate property is configured."),
            .subtasks: .lossless,
            .recurrence: .lossless,
            .reminders: .unsupported(reason: "Reminders are scheduled by Finally on-device."),
            .externalReferences: .unsupported(reason: "No external-reference property is configured."),
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

    /// A run in flight, paired with the dirty records it could see when it started.
    private struct ActiveSynchronization {
        let task: Task<Void, Error>
        let visibleDirtyTaskIDs: Set<PersistentIdentifier>
    }

    let providerIdentity: TaskProviderIdentity
    let capabilities: Set<TaskProviderCapability>
    private let synchronizeProvider: ((TaskProviderSyncIntent, UserSession?, ModelContext) async throws -> Void)?
    private let notionAdapter: SyncService
    private let credentials: FinallyServerCredentialStore
    @ObservationIgnored private var activeSynchronizations: [SynchronizationKey: ActiveSynchronization] = [:]

    var isSyncing = false
    var lastError: String?
    var lastWarning: String?

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
        // An in-flight push read its dirty list when it started. A record dirtied after that read
        // is invisible to it, so joining the push and returning would report success over a change
        // that never left the device. Join the push, then run again for whatever it could not see.
        while let activeSynchronization = activeSynchronizations[key] {
            try await activeSynchronization.task.value
            guard intent == .push else { return }
            let unseen = try pendingChangeIdentifiers(workspace: selectedWorkspace, store: store)
                .subtracting(activeSynchronization.visibleDirtyTaskIDs)
            guard !unseen.isEmpty else { return }
        }

        try await runSynchronization(intent, workspace: selectedWorkspace, store: store, key: key)
    }

    @MainActor
    private func runSynchronization(
        _ intent: TaskProviderSyncIntent,
        workspace: UserSession?,
        store: ModelContext,
        key: SynchronizationKey
    ) async throws {
        let visibleDirtyTaskIDs = try pendingChangeIdentifiers(workspace: workspace, store: store)
        let synchronization = Task { [self] in
            // Release the slot as the provider run finishes so a waiting push can start a
            // follow-up run for changes that arrived in flight.
            defer {
                activeSynchronizations.removeValue(forKey: key)
                isSyncing = !activeSynchronizations.isEmpty
            }
            try await performSynchronization(intent, workspace: workspace, store: store)
        }
        activeSynchronizations[key] = ActiveSynchronization(
            task: synchronization,
            visibleDirtyTaskIDs: visibleDirtyTaskIDs
        )
        isSyncing = true
        lastError = nil
        do {
            try await synchronization.value
            try? WidgetTaskSnapshotStore.publish(store: store)
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func pendingChangeIdentifiers(
        workspace: UserSession?,
        store: ModelContext
    ) throws -> Set<PersistentIdentifier> {
        let dirtyTasks = try store.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDirty == true })
        )
        guard let workspaceID = workspace?.workspaceId else {
            return Set(dirtyTasks.map(\.persistentModelID))
        }
        return Set(
            dirtyTasks
                .filter { $0.providerWorkspaceId == workspaceID }
                .map(\.persistentModelID)
        )
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
            lastWarning = unsupportedFieldWarning(for: tasks, workspaces: workspaces)
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
        try? WidgetTaskSnapshotStore.publish(store: store)
    }

    func clearError() {
        lastError = nil
    }

    func clearWarning() {
        lastWarning = nil
    }

    private func unsupportedFieldWarning(
        for tasks: [TaskItem],
        workspaces: [UserSession]
    ) -> String? {
        let workspaceByID = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.workspaceId, $0) })
        var unsupportedFields: Set<CanonicalTaskField> = []
        for task in tasks {
            guard let workspaceID = task.providerWorkspaceId,
                  let workspace = workspaceByID[workspaceID] else { continue }
            let support: [CanonicalTaskField: TaskProviderFieldSupport]
            switch workspace.providerIdentity {
            case .notion:
                support = notionAdapter.fieldSupport
            case .finallyServer:
                support = FinallyServerTaskProviderAdapter.canonicalFieldSupport
            default:
                support = [:]
            }
            for field in populatedFields(in: task) {
                if case .unsupported = support[field] {
                    unsupportedFields.insert(field)
                }
            }
        }
        guard !unsupportedFields.isEmpty else { return nil }
        let names = unsupportedFields
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
        return "This provider keeps these fields on this device: \(names)."
    }

    private func populatedFields(in task: TaskItem) -> Set<CanonicalTaskField> {
        var fields: Set<CanonicalTaskField> = [.title, .state]
        if task.plannedDay != nil { fields.insert(.plannedDay) }
        if task.deadline != nil { fields.insert(.deadline) }
        if task.project != nil { fields.insert(.project) }
        if !task.tags.isEmpty { fields.insert(.labels) }
        if task.priority != nil { fields.insert(.priority) }
        if task.estimateMinutes != nil { fields.insert(.estimate) }
        if task.isSubtask || task.hasSubtasks { fields.insert(.subtasks) }
        if task.recurrence != .none { fields.insert(.recurrence) }
        if !task.taskReminders.isEmpty { fields.insert(.reminders) }
        if !task.externalReferences.isEmpty { fields.insert(.externalReferences) }
        return fields
    }
}
