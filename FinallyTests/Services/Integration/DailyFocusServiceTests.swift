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

    func testPromptedServerWriteLoadsUnconfirmedAndConfirmationUpdatesTheSameDay() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let task = TaskItem(externalTaskID: "17", title: "Draft the brief")
        task.providerWorkspaceId = server.workspaceId
        task.plannedDay = day
        task.deadline = day.addingTimeInterval(86_400 * 4)
        context.insert(task)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let dayKey = DailyFocus.dayKey(for: tomorrow)
        _ = try await api.writeDailyFocus(projectID: 42, day: dayKey, mutation: FinallyServerDailyFocusMutation(
            picks: [FinallyServerDailyFocusPick(provider: "finally-server", workspaceID: server.workspaceId, externalTaskID: "17")],
            isConfirmed: false, focusLimit: 3
        ))
        let service = DailyFocusService(serverClient: { _ in api })
        let focus = try await service.dailyFocus(for: tomorrow, workspace: server, store: context)
        let identity = focus.persistentModelID
        XCTAssertFalse(focus.isConfirmed)
        XCTAssertEqual(focus.picks, [task.dailyFocusPick])

        focus.confirm()
        try await service.save(focus, workspace: server, store: context)

        XCTAssertEqual(focus.persistentModelID, identity)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyFocus>()), 1)
        let stored = try XCTUnwrap(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: dayKey)])
        XCTAssertTrue(stored.isConfirmed)
        XCTAssertEqual(stored.picks.map(\.externalTaskID), ["17"])
        XCTAssertEqual(task.plannedDay, day)
        XCTAssertEqual(task.deadline, day.addingTimeInterval(86_400 * 4))
        XCTAssertFalse(task.isDirty)
    }

    func testOfflineKeepPersistsBothDaysAndRetriesBothServerWrites() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let task = TaskItem(externalTaskID: "17", title: "Draft the brief")
        task.providerWorkspaceId = server.workspaceId
        context.insert(task)
        let service = DailyFocusService(serverClient: { _ in api })
        let source = try await service.dailyFocus(for: day, workspace: server, store: context)
        try source.add(task.dailyFocusPick)
        try await service.save(source, workspace: server, store: context)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let target = try await service.dailyFocus(for: tomorrow, workspace: server, store: context)
        try source.replan(task.dailyFocusPick, decision: .keep, task: task, nextFocus: target)
        api.error = FinallyServerClientError.serverUnavailable

        do {
            try await service.save([target, source], workspace: server, store: context)
            XCTFail("Expected a recoverable server failure")
        } catch FinallyServerClientError.serverUnavailable {}
        let fresh = ModelContext(context.container)
        let persisted = try fresh.fetch(FetchDescriptor<DailyFocus>())
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.allSatisfy(\.isDirty))
        XCTAssertTrue(try XCTUnwrap(persisted.first { $0.dayKey == source.dayKey }).picks.isEmpty)
        XCTAssertEqual(try XCTUnwrap(persisted.first { $0.dayKey == target.dayKey }).picks, [task.dailyFocusPick])

        api.error = nil
        await service.retryPendingChanges(store: context)

        XCTAssertFalse(source.isDirty)
        XCTAssertFalse(target.isDirty)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: source.dayKey)]?.picks, [])
        XCTAssertEqual(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: target.dayKey)]?.picks.map(\.externalTaskID), ["17"])
    }

    func testWorkspaceSwitchKeepsFocusRecordsAndRetriesSeparate() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        let notion = makeNotionWorkspace()
        notion.isSelected = false
        context.insert(server)
        context.insert(notion)
        let service = DailyFocusService(serverClient: { _ in api })
        let serverFocus = try await service.dailyFocus(for: day, workspace: server, store: context)
        let pick = DailyFocusPick(providerWorkspaceID: server.workspaceId, externalTaskID: "17")
        try serverFocus.add(pick)
        api.error = FinallyServerClientError.serverUnavailable
        do {
            try await service.save(serverFocus, workspace: server, store: context)
            XCTFail("Expected a server failure")
        } catch FinallyServerClientError.serverUnavailable {}

        let phoneFocus = try await service.dailyFocus(for: day, workspace: notion, store: context)
        XCTAssertTrue(phoneFocus.picks.isEmpty)
        XCTAssertNotEqual(serverFocus.persistentModelID, phoneFocus.persistentModelID)
        server.isSelected = false
        let second = makeServerWorkspace()
        second.workspaceId = "second-server-workspace"
        second.serverProjectID = 99
        context.insert(second)
        api.error = nil
        await service.retryPendingChanges(store: context)
        XCTAssertTrue(serverFocus.isDirty)
        XCTAssertNil(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 99, day: serverFocus.dayKey)])

        second.isSelected = false
        server.isSelected = true
        await service.retryPendingChanges(store: context)
        XCTAssertFalse(serverFocus.isDirty)
        XCTAssertEqual(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: serverFocus.dayKey)]?.picks.map(\.externalTaskID), ["17"])
        XCTAssertTrue(phoneFocus.picks.isEmpty)
    }

    func testServerReadPreservesADecisionMadeDuringTheRequest() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let service = DailyFocusService(serverClient: { _ in api })
        let focus = try await service.dailyFocus(for: day, workspace: server, store: context)
        let pick = DailyFocusPick(providerWorkspaceID: server.workspaceId, externalTaskID: "17")
        try focus.add(pick)
        try await service.save(focus, workspace: server, store: context)
        api.dailyFocusReadHook = {
            focus.remove(pick)
            focus.isDirty = true
            try? context.save()
        }

        _ = try await service.dailyFocus(for: day, workspace: server, store: context)

        XCTAssertTrue(focus.picks.isEmpty)
        XCTAssertTrue(focus.isDirty)
        api.dailyFocusReadHook = nil
        await service.retryPendingChanges(store: context)
        XCTAssertEqual(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: focus.dayKey)]?.picks, [])
    }

    func testServerWriteKeepsEditsMadeDuringTheRequestDirty() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let service = DailyFocusService(serverClient: { _ in api })
        let focus = try await service.dailyFocus(for: day, workspace: server, store: context)
        let pick = DailyFocusPick(providerWorkspaceID: server.workspaceId, externalTaskID: "17")
        try focus.add(pick)
        api.dailyFocusWriteHook = {
            focus.remove(pick)
            focus.isDirty = true
            try? context.save()
        }

        try await service.save(focus, workspace: server, store: context)

        XCTAssertTrue(focus.picks.isEmpty)
        XCTAssertTrue(focus.isDirty)
        api.dailyFocusWriteHook = nil
        await service.retryPendingChanges(store: context)
        XCTAssertFalse(focus.isDirty)
        XCTAssertEqual(api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: focus.dayKey)]?.picks, [])
    }

    func testRetryRepeatsFailedServerReadsUntilTheySucceed() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let server = makeServerWorkspace()
        context.insert(server)
        let dayKey = DailyFocus.dayKey(for: day)
        api.dailyFocus[MockFinallyServerAPIClient.dailyFocusKey(projectID: 42, day: dayKey)] = FinallyServerDailyFocus(
            projectID: 42, day: dayKey,
            picks: [FinallyServerDailyFocusPick(provider: "finally-server", workspaceID: server.workspaceId, externalTaskID: "17")],
            isConfirmed: true, focusLimit: 3
        )
        api.error = FinallyServerClientError.serverUnavailable
        let service = DailyFocusService(serverClient: { _ in api })
        let focus = try await service.dailyFocus(for: day, workspace: server, store: context)
        XCTAssertTrue(focus.picks.isEmpty)
        XCTAssertFalse(focus.isDirty)

        await service.retryPendingChanges(store: context)
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(api.dailyFocusOperations, ["read", "read"])

        api.error = nil
        await service.retryPendingChanges(store: context)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["17"])
        XCTAssertTrue(focus.isConfirmed)
        XCTAssertEqual(api.dailyFocusOperations, ["read", "read", "read"])
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
