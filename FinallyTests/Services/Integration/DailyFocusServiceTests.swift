import SwiftData
import XCTest
@testable import Finally

@MainActor
final class DailyFocusServiceTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_788_000_000)

    func testNotionModeKeepsDailyFocusOnThePhone() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let notion = makeNotionWorkspace()
        context.insert(notion)
        let service = DailyFocusService(serverClient: { _ in api })

        let focus = try await service.dailyFocus(for: day, workspace: notion, store: context)
        try focus.add(DailyFocusPick(providerWorkspaceID: notion.workspaceId, externalTaskID: "page-1"))
        try await service.save(focus, workspace: notion, store: context)

        let reloaded = try await service.dailyFocus(for: day, workspace: notion, store: context)
        XCTAssertEqual(reloaded.picks.map(\.externalTaskID), ["page-1"])
        XCTAssertFalse(reloaded.isDirty)
        XCTAssertTrue(api.dailyFocusOperations.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyFocus>()), 1)
    }

    func testServerModeStoresDailyFocusOnFinallyServer() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        let notion = makeNotionWorkspace()
        notion.isSelected = false
        context.insert(server)
        context.insert(notion)
        let service = DailyFocusService(serverClient: { _ in api })

        let focus = try await service.dailyFocus(for: day, workspace: server, store: context)
        try focus.add(DailyFocusPick(providerWorkspaceID: server.workspaceId, externalTaskID: "17"))
        try focus.add(DailyFocusPick(providerWorkspaceID: notion.workspaceId, externalTaskID: "page-1"))
        try await service.save(focus, workspace: server, store: context)

        let key = MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: DailyFocus.dayKey(for: day))
        let stored = try XCTUnwrap(api.dailyFocus[key])
        XCTAssertEqual(stored.picks, [
            FinallyServerDailyFocusPick(provider: "finally-server", workspaceID: server.workspaceId, externalTaskID: "17"),
            FinallyServerDailyFocusPick(provider: "notion", workspaceID: notion.workspaceId, externalTaskID: "page-1"),
        ])
        XCTAssertFalse(stored.isConfirmed)
        XCTAssertEqual(stored.focusLimit, 3)
        XCTAssertFalse(focus.isDirty)
    }

    func testServerCopyReplacesLocalDailyFocusOnLoad() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let dayKey = DailyFocus.dayKey(for: day)
        api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: dayKey)] = FinallyServerDailyFocus(
            projectID: 42,
            day: dayKey,
            picks: [FinallyServerDailyFocusPick(provider: "finally-server", workspaceID: server.workspaceId, externalTaskID: "17")],
            isConfirmed: true,
            focusLimit: 2
        )
        let service = DailyFocusService(serverClient: { _ in api })

        let focus = try await service.dailyFocus(for: day, workspace: server, store: context)

        XCTAssertEqual(focus.picks, [DailyFocusPick(providerWorkspaceID: server.workspaceId, externalTaskID: "17")])
        XCTAssertTrue(focus.isConfirmed)
        XCTAssertEqual(focus.focusLimit, 2)
        XCTAssertFalse(focus.isDirty)
    }

    func testServerFailureKeepsLocalDailyFocusDirtyUntilTheNextSuccessfulRoundTrip() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let service = DailyFocusService(serverClient: { _ in api })
        let focus = try await service.dailyFocus(for: day, workspace: server, store: context)

        api.error = FinallyServerClientError.serverUnavailable
        try focus.add(DailyFocusPick(providerWorkspaceID: server.workspaceId, externalTaskID: "17"))
        do {
            try await service.save(focus, workspace: server, store: context)
            XCTFail("Expected the server failure to surface")
        } catch FinallyServerClientError.serverUnavailable {}

        XCTAssertTrue(focus.isDirty)
        XCTAssertNotNil(service.lastError)
        let persisted = try XCTUnwrap(context.fetch(FetchDescriptor<DailyFocus>()).first)
        XCTAssertEqual(persisted.picks.map(\.externalTaskID), ["17"])

        api.error = nil
        let recovered = try await service.dailyFocus(for: day, workspace: server, store: context)

        XCTAssertFalse(recovered.isDirty)
        XCTAssertNil(service.lastError)
        let key = MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: DailyFocus.dayKey(for: day))
        XCTAssertEqual(api.dailyFocus[key]?.picks.map(\.externalTaskID), ["17"])
    }

    // MARK: - Helpers

    private func makeNotionWorkspace() -> UserSession {
        UserSession(workspaceId: "notion-workspace", workspaceName: "Shared", providerIdentity: .notion)
    }

    private func makeServerWorkspace() -> UserSession {
        let server = UserSession(
            workspaceId: "server-workspace",
            workspaceName: "Personal Server",
            providerIdentity: .finallyServer
        )
        server.serverBaseURL = "https://tasks.example.com"
        server.serverProjectID = 42
        return server
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
