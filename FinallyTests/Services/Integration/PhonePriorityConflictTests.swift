import XCTest
import SwiftData
@testable import Finally

@MainActor
final class PhonePriorityConflictTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, ModelContext, UserSession, MockFinallyServerAPIClient, TaskItem) {
        let container = try ModelContainer(for: Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let workspace = UserSession(workspaceId: "server", workspaceName: "Personal", providerIdentity: .finallyServer)
        workspace.serverProjectID = 42
        let api = MockFinallyServerAPIClient()
        let remote = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false, deadline: Date(timeIntervalSince1970: 2_000_000_000), revision: 7)
        api.tasks[remote.id] = remote
        let task = TaskItem(externalTaskID: remote.id, title: remote.title)
        task.providerWorkspaceId = workspace.workspaceId
        task.deadline = remote.deadline
        task.deadlineHasTime = true
        task.serverRevision = remote.revision
        task.serverSnapshotJSON = remote.mutation.json
        task.lastSyncedAt = Date()
        context.insert(workspace)
        context.insert(task)
        try context.save()
        return (container, context, workspace, api, task)
    }

    func testNarrowPhonePatchPreservesConcurrentUnrelatedFields() async throws {
        let (_, context, workspace, api, task) = try fixture()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Agent title", isCompleted: false, deadline: task.deadline, priority: .high, revision: 8)
        task.deadline = task.deadline?.addingTimeInterval(3600)
        task.isDirty = true
        try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(api.mutations.first?.changedFields, ["due_date", "deadline_has_time"])
        XCTAssertEqual(api.mutations.first?.baseRevision, 7)
        XCTAssertEqual(task.title, "Agent title")
        XCTAssertEqual(task.priority, .high)
        XCTAssertFalse(task.isDirty)
    }

    func testEditDuringAwaitedPushSurvivesAcknowledgmentAndNextPush() async throws {
        let (_, context, workspace, api, task) = try fixture()
        task.title = "Outgoing title"
        task.isDirty = true
        let laterDeadline = task.deadline!.addingTimeInterval(7200)
        api.updateHook = {
            task.deadline = laterDeadline
            task.status = .inProgress
            task.isDirty = true
            api.updateHook = nil
        }
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(task.deadline, laterDeadline)
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertTrue(task.isDirty)
        XCTAssertEqual(task.serverRevision, 8)
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(api.mutations.last?.changedFields, ["due_date", "deadline_has_time"])
        XCTAssertEqual(api.mutations.last?.baseRevision, 8)
        XCTAssertEqual(api.tasks["1"]?.deadline, laterDeadline)
        XCTAssertFalse(task.isDirty)
    }

    func testCompletionDuringAwaitedPushKeepsItsFinishTime() async throws {
        let (_, context, workspace, api, task) = try fixture()
        task.title = "Outgoing title"
        task.isDirty = true
        let finishedAt = Date(timeIntervalSince1970: 1_900_000_000)
        api.updateHook = {
            task.complete(at: finishedAt)
            api.updateHook = nil
        }
        try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedAt, finishedAt)
        XCTAssertTrue(task.isDirty)
    }

    func testKeepingPhoneCompletionInAConflictKeepsItsFinishTime() throws {
        let (_, _, _, _, task) = try fixture()
        let finishedAt = Date(timeIntervalSince1970: 1_900_000_000)
        task.complete(at: finishedAt)
        task.serverConflictJSON = FinallyServerTaskMutation(title: "Another phone title", isCompleted: false).json
        task.serverConflictFields = ["title"]
        task.resolveServerConflict(keepingPhoneEdits: true)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedAt, finishedAt)
    }

    func testCompletionAndEditedTitleShareOneConditionalWrite() async throws {
        let (_, context, workspace, api, task) = try fixture()
        task.title = "Finished proposal"
        task.status = .done
        task.isDirty = true
        try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(api.taskOperations, ["update"])
        XCTAssertEqual(api.mutations.first?.changedFields, ["title", "done"])
        XCTAssertTrue(api.tasks["1"]!.isCompleted)
    }

    func testConflictPersistsLocalIntentAndAcceptedStateUntilExplicitChoice() async throws {
        let (container, context, workspace, api, task) = try fixture()
        task.title = "My phone title"
        task.isDirty = true
        let accepted = FinallyServerTask(id: "1", projectID: 42, title: "Another phone title", isCompleted: false, deadline: task.deadline, priority: .high, revision: 8)
        api.updateError = FinallyServerClientError.conflict(current: accepted, fields: ["title"])
        do { try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context); XCTFail("Expected conflict") }
        catch FinallyServerClientError.conflict { }
        let persisted = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(persisted.title, "My phone title")
        XCTAssertTrue(persisted.isDirty)
        XCTAssertEqual(persisted.conflictingServerMutation?.title, "Another phone title")
        task.resolveServerConflict(keepingPhoneEdits: true)
        XCTAssertEqual(task.title, "My phone title")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.serverRevision, 8)
        XCTAssertTrue(task.isDirty)
        XCTAssertNil(task.serverConflictJSON)
    }

    func testSavedConflictLeavesUnrelatedTasksSyncingAndStillPulls() async throws {
        let (_, context, workspace, api, task) = try fixture()
        task.title = "My phone title"
        task.isDirty = true
        task.serverConflictJSON = FinallyServerTaskMutation(title: "Another phone title", isCompleted: false).json
        task.serverConflictFields = ["title"]
        let other = try syncedTask("2", title: "Groceries", api: api, workspace: workspace, context: context)
        other.title = "Groceries and milk"
        other.isDirty = true
        api.tasks["3"] = FinallyServerTask(id: "3", projectID: 42, title: "Agent capture", isCompleted: false, revision: 1)

        do { try await FinallyServerTaskProviderAdapter(api: api).synchronize(.incremental, workspace: workspace, store: context); XCTFail("Expected conflict") }
        catch FinallyServerClientError.conflict { }

        XCTAssertEqual(api.tasks["2"]?.title, "Groceries and milk")
        XCTAssertFalse(other.isDirty)
        XCTAssertEqual(api.tasks["1"]?.title, "Proposal")
        XCTAssertTrue(task.isDirty)
        XCTAssertNotNil(task.serverConflictJSON)
        let titles = try context.fetch(FetchDescriptor<TaskItem>()).map(\.title)
        XCTAssertTrue(titles.contains("Agent capture"))
    }

    func testMissingTaskLeavesUnrelatedTasksSyncing() async throws {
        let (_, context, workspace, api, task) = try fixture()
        task.title = "Phone recovery"
        task.isDirty = true
        task.serverTaskMissing = true
        let other = try syncedTask("2", title: "Groceries", api: api, workspace: workspace, context: context)
        other.title = "Groceries and milk"
        other.isDirty = true

        do { try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context); XCTFail("Expected missing task") }
        catch FinallyServerClientError.notFound { }

        XCTAssertEqual(api.tasks["2"]?.title, "Groceries and milk")
        XCTAssertFalse(other.isDirty)
        XCTAssertTrue(task.serverTaskMissing)
        XCTAssertEqual(task.title, "Phone recovery")
    }

    private func syncedTask(_ id: String, title: String, api: MockFinallyServerAPIClient, workspace: UserSession, context: ModelContext) throws -> TaskItem {
        let remote = FinallyServerTask(id: id, projectID: 42, title: title, isCompleted: false, revision: 3)
        api.tasks[id] = remote
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = workspace.workspaceId
        task.serverRevision = remote.revision
        task.serverSnapshotJSON = remote.mutation.json
        task.lastSyncedAt = Date()
        context.insert(task)
        try context.save()
        return task
    }

    func testAcceptServerStateClearsDirtyEditAndPendingDeletion() async throws {
        let (_, _, _, _, task) = try fixture()
        task.title = "Phone title"
        task.isDeleted = true
        task.isDirty = true
        task.serverConflictJSON = FinallyServerTaskMutation(title: "Server title", isCompleted: true).json
        task.resolveServerConflict(keepingPhoneEdits: false)
        XCTAssertEqual(task.title, "Server title")
        XCTAssertEqual(task.status, .done)
        XCTAssertFalse(task.isDeleted)
        XCTAssertFalse(task.isDirty)
    }

    func testUsingTheServersVersionReschedulesItsRemindersAndRewritesTheWidget() async throws {
        let (_, context, _, api, task) = try fixture()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let phoneReminder = TaskReminder.exact(ExactReminder(at: now.addingTimeInterval(60)))
        let serverReminder = TaskReminder.exact(ExactReminder(at: now.addingTimeInterval(120)))
        task.taskReminders = [phoneReminder]
        task.isDirty = true
        task.serverConflictJSON = FinallyServerTaskMutation(
            title: "Proposal", deadline: task.deadline, deadlineHasTime: true, reminders: [serverReminder]
        ).json
        let service = NotificationService.shared
        await service.waitUntilIdle()
        let originalCenter = service.center
        let originalClock = service.now
        let center = MockNotificationScheduler()
        service.center = center
        service.now = { now }
        defer { service.center = originalCenter; service.now = originalClock }
        service.rescheduleAllReminders(modelContext: context)
        await service.waitUntilIdle()
        XCTAssertEqual(Array(center.pending.keys), [phoneReminder.notificationId(for: task)])
        let storage = makeWidgetStorage()

        try TaskProviderCoordinator(adapter: FinallyServerTaskProviderAdapter(api: api))
            .resolveConflict(for: task, keepingPhoneEdits: false, store: context, widgetStorage: storage)
        await service.waitUntilIdle()

        XCTAssertFalse(task.isDirty)
        XCTAssertEqual(Array(center.pending.keys), [serverReminder.notificationId(for: task)])
        XCTAssertNotNil(storage.snapshot)
    }

    private func makeWidgetStorage() -> WidgetStorage {
        let suite = "PhonePriorityConflictTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return WidgetStorage(defaults: defaults, completionsDirectory: directory)
    }

    func testRemoteDeletionFinishesPendingPhoneDelete() async throws {
        let (_, context, workspace, api, task) = try fixture()
        api.tasks.removeAll()
        task.isDirty = true
        task.isDeleted = true
        try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    func testRemoteDeletionKeepsEditForExplicitSaveAsNewTask() async throws {
        let (_, context, workspace, api, task) = try fixture()
        api.tasks.removeAll()
        task.title = "Phone recovery"
        task.isDirty = true
        do { try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context); XCTFail("Expected missing task") }
        catch FinallyServerClientError.notFound { }
        XCTAssertTrue(task.serverTaskMissing)
        XCTAssertEqual(task.title, "Phone recovery")
        api.nextTaskID = 2
        try task.saveMissingServerTaskAsDraft(in: context)
        try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(task.externalTaskID, "2")
        XCTAssertEqual(api.tasks["2"]?.title, "Phone recovery")
        XCTAssertFalse(task.isDirty)
    }

    func testSavingMissingTaskAsNewKeepsItsDailyFocusPick() async throws {
        let (_, context, workspace, api, task) = try fixture()
        let focus = DailyFocus(day: Calendar.current.startOfDay(for: Date()), storageWorkspaceID: workspace.workspaceId)
        try focus.add(task.dailyFocusPick)
        context.insert(focus)
        try context.save()
        api.tasks.removeAll()
        task.title = "Phone recovery"
        task.isDirty = true
        do { try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context); XCTFail("Expected missing task") }
        catch FinallyServerClientError.notFound { }
        api.nextTaskID = 2
        try task.saveMissingServerTaskAsDraft(in: context)
        XCTAssertEqual(focus.picks, [task.dailyFocusPick])
        XCTAssertTrue(focus.isDirty)
        focus.isDirty = false
        try await FinallyServerTaskProviderAdapter(api: api).synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(focus.picks, [DailyFocusPick(providerWorkspaceID: workspace.workspaceId, externalTaskID: "2")])
        XCTAssertTrue(focus.resolvedPicks(among: [task]).allSatisfy(\.isAvailable))
        XCTAssertTrue(focus.isDirty)
    }

    func testTimedRemoteScheduledDayProducesTitleOnlyPatch() async throws {
        let (_, context, workspace, api, task) = try fixture()
        let timed = Date(timeIntervalSince1970: 2_000_010_000)
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Proposal", isCompleted: false, scheduledDay: timed, revision: 8)
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        try await adapter.synchronize(.full, workspace: workspace, store: context)
        XCTAssertEqual(task.scheduledDay, Calendar.current.startOfDay(for: timed))
        task.title = "Title edit"
        task.isDirty = true
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(api.mutations.first?.changedFields, ["title"])
    }
}
