import Foundation
import SwiftData

protocol FinallyServerCredentialStore: AnyObject {
    func saveToken(_ token: String, workspaceID: String) throws
    func token(workspaceID: String) -> String?
    func deleteToken(workspaceID: String)
}

final class KeychainFinallyServerCredentialStore: FinallyServerCredentialStore {
    private let service = "com.kaungzinye.finally.server"

    func saveToken(_ token: String, workspaceID: String) throws {
        try KeychainHelper.save(token, service: service, account: workspaceID)
    }

    func token(workspaceID: String) -> String? {
        KeychainHelper.read(service: service, account: workspaceID)
    }

    func deleteToken(workspaceID: String) {
        KeychainHelper.delete(service: service, account: workspaceID)
    }
}

@MainActor
final class FinallyServerAccountService {
    private let api: FinallyServerAPIClient
    private let authenticatedAPI: (String) -> FinallyServerAPIClient
    private let credentials: FinallyServerCredentialStore

    init(api: FinallyServerAPIClient, credentials: FinallyServerCredentialStore = KeychainFinallyServerCredentialStore()) {
        self.api = api
        authenticatedAPI = { _ in api }
        self.credentials = credentials
    }

    init(
        api: FinallyServerAPIClient,
        authenticatedAPI: @escaping (String) -> FinallyServerAPIClient,
        credentials: FinallyServerCredentialStore = KeychainFinallyServerCredentialStore()
    ) {
        self.api = api
        self.authenticatedAPI = authenticatedAPI
        self.credentials = credentials
    }

    func authenticate(
        baseURL: URL,
        username: String,
        password: String
    ) async throws -> FinallyServerAuthenticatedAccount {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil else {
            throw FinallyServerClientError.invalidConfiguration
        }
        let token = try await api.login(username: username, password: password)
        let projects = try await authenticatedAPI(token).listProjects()
        return FinallyServerAuthenticatedAccount(token: token, projects: projects)
    }

    func connect(
        name: String,
        baseURL: URL,
        project: FinallyServerProject,
        account: FinallyServerAuthenticatedAccount,
        store: ModelContext
    ) throws -> UserSession {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              account.projects.contains(project) else {
            throw FinallyServerClientError.invalidConfiguration
        }
        let workspace = UserSession(
            workspaceId: UUID().uuidString,
            workspaceName: name,
            providerIdentity: .finallyServer
        )
        workspace.serverBaseURL = baseURL.absoluteString
        workspace.serverProjectID = project.id

        let sessions = try store.fetch(FetchDescriptor<UserSession>())
        sessions.forEach { $0.isSelected = false }
        workspace.isSelected = true
        try credentials.saveToken(account.token, workspaceID: workspace.workspaceId)
        store.insert(workspace)
        let localProject = ProjectItem(
            externalProjectID: String(project.id),
            title: project.title
        )
        localProject.providerWorkspaceId = workspace.workspaceId
        store.insert(localProject)
        try store.save()
        return workspace
    }

    func remove(_ workspace: UserSession, store: ModelContext) throws {
        try Self.remove(workspace, store: store, credentials: credentials)
    }

    static func remove(
        _ workspace: UserSession,
        store: ModelContext,
        credentials: FinallyServerCredentialStore = KeychainFinallyServerCredentialStore()
    ) throws {
        let workspaceID = workspace.workspaceId
        let tasks = try store.fetch(FetchDescriptor<TaskItem>()).filter {
            $0.providerWorkspaceId == workspaceID
        }
        tasks.forEach(store.delete)
        let projects = try store.fetch(FetchDescriptor<ProjectItem>()).filter {
            $0.providerWorkspaceId == workspaceID
        }
        projects.forEach(store.delete)
        store.delete(workspace)
        let remaining = try store.fetch(FetchDescriptor<UserSession>())
        if !remaining.contains(where: \.isSelected) {
            remaining.first?.isSelected = true
        }
        try store.save()
        credentials.deleteToken(workspaceID: workspaceID)
    }
}

struct FinallyServerAuthenticatedAccount: Sendable {
    fileprivate let token: String
    let projects: [FinallyServerProject]
}
