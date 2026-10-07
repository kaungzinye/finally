import Foundation
import Observation
import SwiftData

/// Loads and saves the Daily Focus for a day. A Finally Server workspace keeps its copy on the
/// server, so loads pull the server copy and saves push the local one. Every other workspace keeps
/// the Daily Focus on the phone. A load always returns the phone copy, and a failed server round
/// trip is reported through `lastError` instead of hiding the Daily Focus.
@Observable
final class DailyFocusService {
    typealias ServerClientFactory = (UserSession) -> FinallyServerAPIClient?

    private let serverClient: ServerClientFactory
    var lastError: String?

    func clearError() {
        lastError = nil
    }

    init(serverClient: @escaping ServerClientFactory = DailyFocusService.keychainServerClient) {
        self.serverClient = serverClient
    }

    static func keychainServerClient(for workspace: UserSession) -> FinallyServerAPIClient? {
        guard let urlString = workspace.serverBaseURL,
              let baseURL = URL(string: urlString),
              let token = KeychainFinallyServerCredentialStore().token(workspaceID: workspace.workspaceId) else {
            return nil
        }
        return URLSessionFinallyServerAPIClient(baseURL: baseURL, token: token)
    }

    @MainActor
    func dailyFocus(
        for day: Date,
        workspace: UserSession?,
        store: ModelContext,
        focusLimit: Int = DailyFocus.defaultFocusLimit
    ) async throws -> DailyFocus {
        let dayStart = Calendar.current.startOfDay(for: day)
        let focus: DailyFocus
        if let existing = try localDailyFocus(for: dayStart, store: store) {
            focus = existing
        } else {
            focus = DailyFocus(day: dayStart, focusLimit: focusLimit)
            store.insert(focus)
            try store.save()
        }
        guard let workspace, workspace.providerIdentity == .finallyServer else { return focus }
        do {
            if focus.isDirty {
                try await push(focus, workspace: workspace, store: store)
            } else {
                try await pull(into: focus, workspace: workspace, store: store)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error.localizedDescription
        }
        return focus
    }

    @MainActor
    func save(_ focus: DailyFocus, workspace: UserSession?, store: ModelContext) async throws {
        guard let workspace, workspace.providerIdentity == .finallyServer else {
            focus.isDirty = false
            try store.save()
            return
        }
        focus.isDirty = true
        try store.save()
        try await push(focus, workspace: workspace, store: store)
    }

    // MARK: - Finally Server round trips

    @MainActor
    private func pull(into focus: DailyFocus, workspace: UserSession, store: ModelContext) async throws {
        let (api, projectID) = try client(for: workspace)
        do {
            guard let record = try await api.readDailyFocus(projectID: projectID, day: focus.dayKey) else {
                try await push(focus, workspace: workspace, store: store)
                return
            }
            focus.picks = record.picks.map {
                DailyFocusPick(providerWorkspaceID: $0.workspaceID, externalTaskID: $0.externalTaskID)
            }
            focus.isConfirmed = record.isConfirmed
            focus.focusLimit = DailyFocus.clampedFocusLimit(record.focusLimit)
            focus.isDirty = false
            try store.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    @MainActor
    private func push(_ focus: DailyFocus, workspace: UserSession, store: ModelContext) async throws {
        let (api, projectID) = try client(for: workspace)
        let providers = Dictionary(
            try store.fetch(FetchDescriptor<UserSession>()).map { ($0.workspaceId, $0.providerIdentity.rawValue) },
            uniquingKeysWith: { first, _ in first }
        )
        let mutation = FinallyServerDailyFocusMutation(
            picks: focus.picks.map {
                FinallyServerDailyFocusPick(
                    provider: providers[$0.providerWorkspaceID] ?? "unknown",
                    workspaceID: $0.providerWorkspaceID,
                    externalTaskID: $0.externalTaskID
                )
            },
            isConfirmed: focus.isConfirmed,
            focusLimit: focus.focusLimit
        )
        do {
            _ = try await api.writeDailyFocus(projectID: projectID, day: focus.dayKey, mutation: mutation)
            focus.isDirty = false
            try store.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func client(for workspace: UserSession) throws -> (FinallyServerAPIClient, Int64) {
        guard let api = serverClient(workspace) else { throw FinallyServerClientError.unauthorized }
        guard let projectID = workspace.serverProjectID else { throw FinallyServerClientError.invalidConfiguration }
        return (api, projectID)
    }

    private func localDailyFocus(for dayStart: Date, store: ModelContext) throws -> DailyFocus? {
        try store.fetch(FetchDescriptor<DailyFocus>(predicate: #Predicate { $0.day == dayStart })).first
    }
}
