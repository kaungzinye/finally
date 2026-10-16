import XCTest
import SwiftData
@testable import Finally

@MainActor
final class ServerReminderSyncTests: XCTestCase {
    func testProviderPullReconcilesRulesAndRemoteCompletion() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ModelContext(container)
        let workspace = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        workspace.serverProjectID = 42
        store.insert(workspace)
        let api = MockFinallyServerAPIClient()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reminder = TaskReminder.exact(ExactReminder(at: now.addingTimeInterval(60)))
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false, revision: 7, reminders: [reminder])
        let service = NotificationService.shared
        await service.waitUntilIdle()
        let originalCenter = service.center
        let originalClock = service.now
        let center = MockNotificationScheduler()
        service.center = center
        service.now = { now }
        defer { service.center = originalCenter; service.now = originalClock }
        let coordinator = TaskProviderCoordinator(adapter: FinallyServerTaskProviderAdapter(api: api))
        try await coordinator.synchronize(.full, workspace: workspace, store: store)
        await service.waitUntilIdle()
        XCTAssertEqual(center.pending.count, 1)
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: true, revision: 8, reminders: [reminder])
        try await coordinator.synchronize(.full, workspace: workspace, store: store)
        await service.waitUntilIdle()
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(try store.fetch(FetchDescriptor<TaskItem>()).first?.taskReminders, [reminder])
    }

    func testRulesAndDateOnlyPrecisionRoundTripAndDirtyReminderEditSurvivesPull() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ModelContext(container)
        let workspace = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        workspace.serverProjectID = 42
        store.insert(workspace)
        let deadlineReminder = TaskReminder.deadline(DeadlineReminder(offset: .hourBefore))
        let exact = TaskReminder.exact(ExactReminder(at: Date(timeIntervalSince1970: 2_000_000_000.125)))
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false,
                                          deadline: Date(timeIntervalSince1970: 2_000_000_000), revision: 7,
                                          deadlineHasTime: false, reminders: [deadlineReminder, exact])
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        try await adapter.synchronize(.launch, workspace: workspace, store: store)
        let task = try XCTUnwrap(store.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertFalse(task.deadlineHasTime)
        XCTAssertEqual(task.taskReminders, [deadlineReminder, exact])
        task.taskReminders = [exact]
        task.isDirty = true
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Accepted title", isCompleted: false,
                                          deadline: task.deadline, revision: 8, deadlineHasTime: false, reminders: [deadlineReminder, exact])
        try await adapter.synchronize(.full, workspace: workspace, store: store)
        XCTAssertEqual(task.taskReminders, [exact])
        XCTAssertTrue(task.isDirty)
        try await adapter.synchronize(.push, workspace: workspace, store: store)
        XCTAssertEqual(api.mutations.last?.changedFields, ["reminder_rules"])
        XCTAssertEqual(api.mutations.last?.baseRevision, 7)
        XCTAssertEqual(task.title, "Accepted title")
        XCTAssertFalse(task.deadlineHasTime)
        XCTAssertEqual(api.tasks["1"]?.reminders, [exact])
        XCTAssertFalse(task.isDirty)
    }

    /// Finally Server carries reminder rules, so a pulled deadline keeps the server's rules and
    /// receives no phone defaults.
    func testPulledDeadlineKeepsTheServersRulesWithoutDefaults() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ModelContext(container)
        let workspace = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        workspace.serverProjectID = 42
        store.insert(workspace)
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false, revision: 7)
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        try await adapter.synchronize(.launch, workspace: workspace, store: store)
        let task = try XCTUnwrap(store.fetch(FetchDescriptor<TaskItem>()).first)

        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false,
                                          deadline: Date(timeIntervalSince1970: 2_000_000_000), revision: 8,
                                          deadlineHasTime: true)
        try await adapter.synchronize(.full, workspace: workspace, store: store)

        XCTAssertNotNil(task.deadline)
        XCTAssertTrue(task.taskReminders.isEmpty)
        XCTAssertFalse(task.isDirty)
    }

    func testPhoneDeadlineEditPushesTheDefaultRulesWithTheDeadline() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ModelContext(container)
        let workspace = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        workspace.serverProjectID = 42
        store.insert(workspace)
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false, revision: 7)
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        try await adapter.synchronize(.launch, workspace: workspace, store: store)
        let task = try XCTUnwrap(store.fetch(FetchDescriptor<TaskItem>()).first)

        task.setDeadline(Date(timeIntervalSince1970: 2_000_000_000), hasTime: false, defaults: .standard)
        task.isDirty = true
        try await adapter.synchronize(.push, workspace: workspace, store: store)

        XCTAssertEqual(api.mutations.last?.changedFields, ["due_date", "deadline_has_time", "reminder_rules"])
        XCTAssertEqual(api.tasks["1"]?.reminders, task.taskReminders)
        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1)])
        XCTAssertFalse(task.isDirty)
    }

    func testReminderEditDuringPushKeepsIntentAndReturnedRevision() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ModelContext(container)
        let workspace = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        workspace.serverProjectID = 42
        store.insert(workspace)
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false, revision: 7)
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        try await adapter.synchronize(.launch, workspace: workspace, store: store)
        let task = try XCTUnwrap(store.fetch(FetchDescriptor<TaskItem>()).first)
        task.title = "Phone title"
        task.isDirty = true
        let reminder = TaskReminder.exact(ExactReminder(at: Date(timeIntervalSince1970: 2_000_000_000)))
        api.updateHook = { task.taskReminders = [reminder]; task.isDirty = true; api.updateHook = nil }
        try await adapter.synchronize(.push, workspace: workspace, store: store)
        XCTAssertEqual(task.taskReminders, [reminder])
        XCTAssertTrue(task.isDirty)
        XCTAssertEqual(task.serverRevision, 8)
        try await adapter.synchronize(.push, workspace: workspace, store: store)
        XCTAssertEqual(api.mutations.last?.changedFields, ["reminder_rules"])
        XCTAssertEqual(api.mutations.last?.baseRevision, 8)
        XCTAssertFalse(task.isDirty)
    }
}
