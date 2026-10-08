import SwiftData
import XCTest
@testable import Finally

@MainActor
final class NotionOnboardingIntegrationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testOAuthCompletionStoresInCallerContextAndRoutesToDatabaseSetup() async throws {
        let store = try makeStore()
        let server = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        store.insert(server)
        try store.save()
        var savedToken: String?
        let auth = makeAuth { savedToken = $0 }
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"access_token":"test-token","workspace_id":"notion","workspace_name":"My tasks","bot_id":"bot"}"#.utf8)
            )
        }

        let success = await auth.completeOAuth(withCode: "test-code", modelContext: store)

        XCTAssertTrue(success)
        XCTAssertEqual(savedToken, "test-token")
        XCTAssertFalse(auth.isAuthenticating)
        XCTAssertNil(auth.errorMessage)
        let selected = try XCTUnwrap(store.selectedProviderWorkspace())
        XCTAssertEqual(selected.workspaceId, "notion")
        XCTAssertEqual(ProviderSessionRoute.resolve(selectedWorkspace: selected), .databaseSetup)
        XCTAssertFalse(server.isSelected)
        XCTAssertEqual(try store.fetchCount(FetchDescriptor<UserSession>()), 2)
        let persisted = ModelContext(store.container)
        XCTAssertEqual(try persisted.selectedProviderWorkspace()?.workspaceId, "notion")
    }

    func testAuthorizationRefreshKeepsConfiguredDatabaseAndTaskIdentity() throws {
        let store = try makeStore()
        let notion = UserSession(workspaceId: "notion", workspaceName: "Tasks", providerIdentity: .notion)
        notion.tasksDatabaseId = "tasks-db"
        notion.projectsDatabaseId = "projects-db"
        store.insert(notion)
        let task = TaskItem(externalTaskID: "task", title: "Write the brief")
        task.providerWorkspaceId = notion.workspaceId
        store.insert(task)
        try store.save()
        let auth = makeAuth { _ in }

        try auth.storeSession(
            tokenResponse: .init(accessToken: "test-token", workspaceId: "notion", workspaceName: "Team", botId: "bot"),
            modelContext: store
        )

        let selected = try XCTUnwrap(store.selectedProviderWorkspace())
        XCTAssertEqual(selected.id, notion.id)
        XCTAssertEqual(selected.workspaceName, "Team")
        XCTAssertEqual(selected.tasksDatabaseId, "tasks-db")
        XCTAssertEqual(selected.projectsDatabaseId, "projects-db")
        XCTAssertEqual(ProviderSessionRoute.resolve(selectedWorkspace: selected), .tasks)
        XCTAssertEqual(try store.fetchCount(FetchDescriptor<UserSession>()), 1)
        XCTAssertEqual(try store.fetch(FetchDescriptor<TaskItem>()).first?.dailyFocusPick, task.dailyFocusPick)
    }

    func testFailedExchangeLeavesSelectedServerAndAllowsRetry() async throws {
        let store = try makeStore()
        let server = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        store.insert(server)
        try store.save()
        var tokenWrites = 0
        let auth = makeAuth { _ in tokenWrites += 1 }
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }

        let success = await auth.completeOAuth(withCode: "rejected-code", modelContext: store)

        XCTAssertFalse(success)
        XCTAssertFalse(auth.isAuthenticating)
        XCTAssertNotNil(auth.errorMessage)
        XCTAssertEqual(tokenWrites, 0)
        XCTAssertEqual(try store.selectedProviderWorkspace()?.id, server.id)
        XCTAssertEqual(try store.fetchCount(FetchDescriptor<UserSession>()), 1)
    }

    func testCredentialFailureLeavesWorkspaceSelectionIntact() throws {
        let store = try makeStore()
        let server = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        store.insert(server)
        try store.save()
        let auth = makeAuth { _ in throw KeychainHelper.KeychainError.itemNotFound }

        XCTAssertThrowsError(try auth.storeSession(
            tokenResponse: .init(accessToken: "test-token", workspaceId: "notion", workspaceName: "Team", botId: "bot"),
            modelContext: store
        ))

        XCTAssertTrue(server.isSelected)
        XCTAssertEqual(try store.fetchCount(FetchDescriptor<UserSession>()), 1)
    }

    func testCallbackRequiresFinallyOAuthURLAndNonemptyCode() {
        let auth = makeAuth { _ in }
        XCTAssertEqual(auth.extractAuthCode(from: URL(string: "finally://oauth-callback?code=valid")!), "valid")
        XCTAssertNil(auth.extractAuthCode(from: URL(string: "finally://oauth-callback?code=")!))
        XCTAssertNil(auth.extractAuthCode(from: URL(string: "finally://tasks/new?code=valid")!))
        XCTAssertNil(auth.extractAuthCode(from: URL(string: "https://oauth-callback?code=valid")!))
    }

    func testRootRoutesEmptyAndServerWorkspaces() {
        XCTAssertEqual(ProviderSessionRoute.resolve(selectedWorkspace: nil), .connect)
        let server = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        XCTAssertEqual(ProviderSessionRoute.resolve(selectedWorkspace: server), .tasks)
    }

    private func makeAuth(saveToken: @escaping (String) throws -> Void) -> NotionAuthService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return NotionAuthService(urlSession: URLSession(configuration: configuration), saveToken: saveToken)
    }

    private func makeStore() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }
}
