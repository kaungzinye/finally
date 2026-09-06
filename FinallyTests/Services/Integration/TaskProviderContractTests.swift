import SwiftData
import XCTest
@testable import Finally

final class TaskProviderContractTests: XCTestCase {
    func testUnsyncedCreateIsDurableBeforeThrowingProviderPush() async throws {
        let (container, context) = try makeInMemoryStore()
        let adapter = AlwaysFailingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let workspace = UserSession(workspaceId: "workspace", workspaceName: "Workspace", providerIdentity: .notion)
        context.insert(workspace)
        let task = TaskItem(externalTaskID: "local-draft", title: "Draft survives")
        task.providerWorkspaceId = workspace.workspaceId
        task.isDirty = true
        context.insert(task)

        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TaskItem>()), 0)
        try coordinator.persistPendingChanges(store: context)
        do {
            try await coordinator.synchronize(.push, workspace: workspace, store: context)
            XCTFail("Expected provider failure")
        } catch AlwaysFailingTaskProviderAdapter.Failure.offline {
            let persisted = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
            XCTAssertEqual(persisted.map(\.title), ["Draft survives"])
            XCTAssertTrue(try XCTUnwrap(persisted.first).isDirty)
            XCTAssertEqual(adapter.synchronizeCallCount, 1)
        }
    }

    func testUnsyncedEditIsDurableBeforeThrowingProviderPush() async throws {
        let (container, context) = try makeInMemoryStore()
        let adapter = AlwaysFailingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let workspace = UserSession(workspaceId: "workspace", workspaceName: "Workspace", providerIdentity: .notion)
        let task = TaskItem(externalTaskID: "remote-task", title: "Original")
        task.providerWorkspaceId = workspace.workspaceId
        context.insert(workspace)
        context.insert(task)
        try context.save()

        task.title = "Edited while offline"
        task.isDirty = true
        XCTAssertEqual(
            try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TaskItem>()).first).title,
            "Original"
        )
        try coordinator.persistPendingChanges(store: context)
        do {
            try await coordinator.synchronize(.push, workspace: workspace, store: context)
            XCTFail("Expected provider failure")
        } catch AlwaysFailingTaskProviderAdapter.Failure.offline {
            let persisted = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
            XCTAssertEqual(try XCTUnwrap(persisted.first).title, "Edited while offline")
            XCTAssertTrue(try XCTUnwrap(persisted.first).isDirty)
            XCTAssertEqual(adapter.synchronizeCallCount, 1)
        }
    }

    func testProviderCoordinatorPushMakesLocalDraftProviderBacked() async throws {
        let mock = MockNotionAPIClient()
        let coordinator = TaskProviderCoordinator(adapter: SyncService(api: mock))
        let context = try makeInMemoryContext()
        let workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared", providerIdentity: .notion)
        workspace.tasksDatabaseId = "tasks-db"
        context.insert(workspace)
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Review proposal")
        task.providerWorkspaceId = workspace.workspaceId
        task.isDirty = true
        context.insert(task)
        try context.save()

        try await coordinator.synchronize(.push, workspace: workspace, store: context)

        XCTAssertEqual(task.externalTaskID, "remote-1")
        XCTAssertFalse(task.isDirty)
    }

    func testMutationSubmissionUsesTaskWorkspace() async throws {
        let adapter = RecordingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let context = try makeInMemoryContext()
        let selectedWorkspace = UserSession(workspaceId: "selected", workspaceName: "Selected", providerIdentity: .notion)
        selectedWorkspace.isSelected = true
        let taskWorkspace = UserSession(workspaceId: "task-workspace", workspaceName: "Task workspace", providerIdentity: .notion)
        taskWorkspace.isSelected = false
        let task = TaskItem(externalTaskID: "task-1", title: "Review proposal")
        task.providerWorkspaceId = taskWorkspace.workspaceId
        task.isDirty = true
        context.insert(selectedWorkspace)
        context.insert(taskWorkspace)
        context.insert(task)

        try await coordinator.submitPendingChanges(for: [task], store: context)

        XCTAssertEqual(adapter.workspaceIDs, ["task-workspace"])
    }

    func testWorkspaceFreeLaunchUsesTheSelectedProviderWorkspace() async throws {
        let adapter = RecordingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let context = try makeInMemoryContext()
        let selected = UserSession(
            workspaceId: "server-workspace",
            workspaceName: "Personal",
            providerIdentity: .finallyServer
        )
        selected.isSelected = true
        context.insert(selected)

        try await coordinator.synchronize(.launch, store: context)

        XCTAssertEqual(adapter.workspaceIDs, [selected.workspaceId])
    }

    func testFailedMutationSubmissionRemainsDurableAndRetriesWithoutDuplicateTask() async throws {
        let api = MockFinallyServerAPIClient()
        api.error = FinallyServerClientError.serverUnavailable
        let coordinator = TaskProviderCoordinator(adapter: FinallyServerTaskProviderAdapter(api: api))
        let (container, context) = try makeInMemoryStore()
        let workspace = UserSession(
            workspaceId: "server-workspace",
            workspaceName: "Personal",
            providerIdentity: .finallyServer
        )
        workspace.serverProjectID = 42
        let task = TaskItem(externalTaskID: "local-draft", title: "Review proposal")
        task.providerWorkspaceId = workspace.workspaceId
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)

        do {
            try await coordinator.submitPendingChanges(for: [task], store: context)
            XCTFail("Expected provider failure")
        } catch FinallyServerClientError.serverUnavailable {
            let durableTasks = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
            XCTAssertEqual(durableTasks.count, 1)
            XCTAssertTrue(try XCTUnwrap(durableTasks.first).isDirty)
            XCTAssertTrue(api.tasks.isEmpty)
        }

        api.error = nil
        try await coordinator.submitPendingChanges(for: [task], store: context)

        XCTAssertEqual(api.tasks.count, 1)
        XCTAssertEqual(task.externalTaskID, "1")
        XCTAssertFalse(task.isDirty)
    }

    @MainActor
    func testConcurrentDuplicateMutationSubmissionsShareOneProviderCall() async throws {
        let adapter = BlockingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let context = try makeInMemoryContext()
        let workspace = UserSession(workspaceId: "workspace", workspaceName: "Workspace", providerIdentity: .notion)
        let task = TaskItem(externalTaskID: "task-1", title: "Review proposal")
        task.providerWorkspaceId = workspace.workspaceId
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)

        let first = Task { @MainActor in
            try await coordinator.submitPendingChanges(for: [task], store: context)
        }
        await adapter.waitUntilStarted()
        let duplicate = Task { @MainActor in
            try await coordinator.submitPendingChanges(for: [task], store: context)
        }
        await Task.yield()

        let callsBeforeRelease = await adapter.callCount
        XCTAssertEqual(callsBeforeRelease, 1)
        await adapter.release()
        try await first.value
        try await duplicate.value
        let callsAfterRelease = await adapter.callCount
        XCTAssertEqual(callsAfterRelease, 1)
    }

    func testChangeDirtiedDuringAnInFlightPushStillReachesTheProvider() async throws {
        let adapter = DirtyDrainingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let context = try makeInMemoryContext()
        let workspace = UserSession(workspaceId: "workspace", workspaceName: "Workspace", providerIdentity: .notion)
        let early = TaskItem(externalTaskID: "task-1", title: "Read before the push")
        early.providerWorkspaceId = workspace.workspaceId
        early.isDirty = true
        context.insert(workspace)
        context.insert(early)
        try context.save()

        let inFlight = Task { @MainActor in
            try await coordinator.submitPendingChanges(for: [early], store: context)
        }
        await adapter.waitUntilFirstArrival()

        let late = TaskItem(externalTaskID: "task-2", title: "Dirtied mid flight")
        late.providerWorkspaceId = workspace.workspaceId
        late.isDirty = true
        context.insert(late)
        try context.save()

        let joining = Task { @MainActor in
            try await coordinator.submitPendingChanges(for: [late], store: context)
        }
        try await Task.sleep(for: .milliseconds(50))
        await adapter.open()
        try await inFlight.value
        try await joining.value

        let arrivals = await adapter.arrivals
        XCTAssertEqual(arrivals, 2)
        XCTAssertEqual(
            adapter.observedDirtyTitles,
            [["Read before the push"], ["Dirtied mid flight"]]
        )
        XCTAssertFalse(early.isDirty)
        XCTAssertFalse(late.isDirty)
    }

    func testNotionAdapterReportsProviderNeutralIdentityAndCapabilities() {
        let adapter: any TaskProviderAdapter = SyncService(api: MockNotionAPIClient())
        let workspace = ProviderWorkspaceIdentity(
            provider: adapter.providerIdentity,
            externalID: "workspace-1"
        )
        let task = ProviderTaskIdentity(workspace: workspace, externalID: "task-1")

        XCTAssertEqual(adapter.providerIdentity, TaskProviderIdentity(rawValue: "notion"))
        XCTAssertEqual(workspace.provider, adapter.providerIdentity)
        XCTAssertEqual(task.workspace, workspace)
        XCTAssertEqual(task.externalID, "task-1")
        XCTAssertEqual(
            adapter.capabilities,
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
        )
    }

    func testProviderConformanceMatrixDeclaresEveryCanonicalField() {
        let notion = SyncService(api: MockNotionAPIClient())
        let server = FinallyServerTaskProviderAdapter(api: MockFinallyServerAPIClient())
        let canonicalFields = Set(CanonicalTaskField.allCases)

        XCTAssertEqual(Set(notion.fieldSupport.keys), canonicalFields)
        XCTAssertEqual(Set(server.fieldSupport.keys), canonicalFields)
        XCTAssertEqual(notion.fieldSupport[.deadline], .lossless)
        XCTAssertEqual(
            notion.fieldSupport[.plannedDay],
            .lossy(reason: "A separate Target date property is required to preserve every planned-day shape.")
        )
        guard case .lossy = server.fieldSupport[.deadline] else {
            return XCTFail("Finally Server timestamp normalization must remain explicit")
        }
        guard case .lossy = server.fieldSupport[.state] else {
            return XCTFail("Finally Server records completion only, so state cannot claim a full round trip")
        }
        guard case .lossy = server.fieldSupport[.project] else {
            return XCTFail("A Finally Server workspace pins one project, so project cannot claim a full round trip")
        }
    }

    func testFinallyServerKeepsDateOnlyPlanningAcrossARoundTrip() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Plan the week")
        task.providerWorkspaceId = workspace.workspaceId
        task.targetDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        task.targetDateHasTime = false
        task.dueDate = Date(timeIntervalSince1970: 1_780_086_400)
        task.dueDateHasTime = true
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)
        let adapter = FinallyServerTaskProviderAdapter(api: api)

        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertFalse(task.targetDateHasTime)
        XCTAssertTrue(task.dueDateHasTime)

        try await adapter.synchronize(.launch, workspace: workspace, store: context)

        XCTAssertFalse(task.targetDateHasTime)
        XCTAssertTrue(task.dueDateHasTime)
    }

    func testFinallyServerReadsARemotelyChangedPlanningDateAsTimed() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(
            id: "1",
            projectID: 42,
            title: "Plan the week",
            isCompleted: false,
            plannedDay: Date(timeIntervalSince1970: 1_780_012_345)
        )
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: "1", title: "Plan the week")
        task.providerWorkspaceId = workspace.workspaceId
        task.targetDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        task.targetDateHasTime = false
        task.lastSyncedAt = Date()
        context.insert(workspace)
        context.insert(task)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.full, workspace: workspace, store: context)

        XCTAssertEqual(task.targetDate, Date(timeIntervalSince1970: 1_780_012_345))
        XCTAssertTrue(task.targetDateHasTime)
    }

    func testFinallyServerKeepsInProgressStateAcrossARoundTrip() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Draft the brief")
        task.providerWorkspaceId = workspace.workspaceId
        task.status = .inProgress
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)
        let adapter = FinallyServerTaskProviderAdapter(api: api)

        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(task.status, .inProgress)

        try await adapter.synchronize(.full, workspace: workspace, store: context)
        XCTAssertEqual(task.status, .inProgress)

        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Draft the brief", isCompleted: true)
        try await adapter.synchronize(.full, workspace: workspace, store: context)
        XCTAssertEqual(task.status, .done)
    }

    /// A Finally Server workspace is exactly one server project, so a task moved to another
    /// project has left this workspace and Finally drops the local record.
    func testFinallyServerRemovesACleanTaskMovedToAnotherServerProject() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["55"] = FinallyServerTask(
            id: "55",
            projectID: 99,
            title: "Moved away",
            isCompleted: false
        )
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: "55", title: "Moved away")
        task.providerWorkspaceId = workspace.workspaceId
        task.lastSyncedAt = Date()
        context.insert(workspace)
        context.insert(task)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.full, workspace: workspace, store: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    private func makeServerWorkspace() -> UserSession {
        let workspace = UserSession(
            workspaceId: "server-workspace",
            workspaceName: "Personal Server",
            providerIdentity: .finallyServer
        )
        workspace.serverProjectID = 42
        return workspace
    }

    func testUnsupportedPopulatedFieldsProduceAProviderNotice() async throws {
        let coordinator = TaskProviderCoordinator(
            adapter: FinallyServerTaskProviderAdapter(api: MockFinallyServerAPIClient())
        )
        let context = try makeInMemoryContext()
        let workspace = UserSession(
            workspaceId: "server-workspace",
            workspaceName: "Personal",
            providerIdentity: .finallyServer
        )
        workspace.serverProjectID = 42
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Plan launch")
        task.providerWorkspaceId = workspace.workspaceId
        task.tags = ["Launch"]
        task.estimateMinutes = 30
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)

        try await coordinator.submitPendingChanges(for: [task], store: context)

        XCTAssertEqual(
            coordinator.lastWarning,
            "This provider keeps these fields on this device: estimate, labels."
        )
    }

    func testCanonicalPlanningFieldsPersistIndependently() throws {
        let (container, context) = try makeInMemoryStore()
        let workspace = UserSession(
            workspaceId: "workspace",
            workspaceName: "Workspace",
            providerIdentity: .notion
        )
        let task = TaskItem(externalTaskID: "task-1", title: "Plan launch")
        task.providerWorkspaceId = workspace.workspaceId
        task.targetDate = Date(timeIntervalSince1970: 1_780_000_000)
        task.targetDateHasTime = false
        task.dueDate = Date(timeIntervalSince1970: 1_780_086_400)
        task.dueDateHasTime = true
        task.priority = .urgent
        task.tags = ["Launch"]
        task.estimateMinutes = 90
        task.recurrence = .weekly
        task.taskReminders = [
            .explicitDate(ExplicitDateReminder(dateTime: Date(timeIntervalSince1970: 1_780_050_000)))
        ]
        task.externalReferences = ["https://example.com/brief"]
        context.insert(workspace)
        context.insert(task)
        try context.save()

        let stored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertNotEqual(stored.targetDate, stored.dueDate)
        XCTAssertFalse(stored.targetDateHasTime)
        XCTAssertTrue(stored.dueDateHasTime)
        XCTAssertEqual(stored.estimateMinutes, 90)
        XCTAssertEqual(stored.externalReferences, ["https://example.com/brief"])
        XCTAssertEqual(stored.taskReminders.count, 1)
    }

    func testNotionAdapterMapsStoredWorkspaceAndTaskIntoProviderNeutralIdentities() {
        let adapter = SyncService(api: MockNotionAPIClient())
        let session = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared", providerIdentity: .notion)
        let task = TaskItem(externalTaskID: "notion-page", title: "Review proposal")

        let workspaceIdentity = adapter.workspaceIdentity(for: session)
        let taskIdentity = adapter.taskIdentity(for: task, in: workspaceIdentity)

        XCTAssertEqual(
            workspaceIdentity,
            ProviderWorkspaceIdentity(
                provider: TaskProviderIdentity(rawValue: "notion"),
                externalID: "notion-workspace"
            )
        )
        XCTAssertEqual(
            taskIdentity,
            ProviderTaskIdentity(workspace: workspaceIdentity, externalID: "notion-page")
        )
    }

    func testNotionAdapterSatisfiesCanonicalTaskLifecycleContract() async throws {
        let mock = MockNotionAPIClient()
        let adapter = SyncService(api: mock)
        let context = try makeInMemoryContext()
        let session = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared", providerIdentity: .notion)
        session.tasksDatabaseId = "tasks-db"
        context.insert(session)
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Review proposal")
        task.providerWorkspaceId = session.workspaceId

        try await assertCanonicalTaskLifecycle(
            using: TaskProviderLifecycleHarness(
                adapter: adapter,
                workspace: session,
                store: context,
                createDraft: {
                    task.isDirty = true
                    context.insert(task)
                    try context.save()
                },
                createdTaskIdentity: {
                    adapter.taskIdentity(
                        for: task,
                        in: adapter.workspaceIdentity(for: session)
                    )
                },
                expectedCreatedExternalID: "remote-1",
                publishRemoteUpdate: {
                    mock.queryAllPagesResult["tasks-db"] = [
                        NotionTestFactory.page(
                            id: "remote-1",
                            properties: [
                                "Name": NotionTestFactory.propertyValue(
                                    type: "title",
                                    title: [NotionRichText(plainText: "Review revised proposal")]
                                ),
                                "Status": NotionTestFactory.propertyValue(
                                    type: "status",
                                    statusName: "In Progress"
                                ),
                                "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: nil),
                            ]
                        )
                    ]
                },
                hasRemoteUpdate: {
                    task.title == "Review revised proposal" && task.status == .inProgress
                },
                completeTask: { task.complete() },
                isComplete: { task.status == .done && !task.isDirty },
                deleteTask: {
                    task.isDeleted = true
                    task.isDirty = true
                },
                archivedTaskIDs: { mock.archivedPageIds },
                localTaskCount: { try context.fetchCount(FetchDescriptor<TaskItem>()) }
            )
        )
    }

    func testFinallyServerAdapterSatisfiesCanonicalTaskLifecycleContract() async throws {
        let api = MockFinallyServerAPIClient()
        let adapter = FinallyServerTaskProviderAdapter(api: api)
        let context = try makeInMemoryContext()
        let session = UserSession(
            workspaceId: "server-workspace",
            workspaceName: "Personal",
            providerIdentity: .finallyServer
        )
        session.serverBaseURL = "https://tasks.example.com"
        session.serverProjectID = 42
        context.insert(session)
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Review proposal")
        task.providerWorkspaceId = session.workspaceId

        try await assertCanonicalTaskLifecycle(
            using: TaskProviderLifecycleHarness(
                adapter: adapter,
                workspace: session,
                store: context,
                createDraft: {
                    task.isDirty = true
                    context.insert(task)
                    try context.save()
                },
                createdTaskIdentity: {
                    adapter.taskIdentity(
                        for: task,
                        in: adapter.workspaceIdentity(for: session)
                    )
                },
                expectedCreatedExternalID: "1",
                publishRemoteUpdate: {
                    api.tasks["1"] = FinallyServerTask(
                        id: "1",
                        projectID: 42,
                        title: "Review revised proposal",
                        isCompleted: false
                    )
                },
                hasRemoteUpdate: {
                    task.title == "Review revised proposal" && task.status == .notStarted
                },
                completeTask: { task.complete() },
                isComplete: { task.status == .done && !task.isDirty },
                deleteTask: {
                    task.isDeleted = true
                    task.isDirty = true
                },
                archivedTaskIDs: { api.tasks["1"] == nil ? ["1"] : [] },
                localTaskCount: { try context.fetchCount(FetchDescriptor<TaskItem>()) }
            )
        )
    }

    private func assertCanonicalTaskLifecycle<Adapter: TaskProviderAdapter>(
        using harness: TaskProviderLifecycleHarness<Adapter>
    ) async throws {
        try harness.createDraft()

        try await harness.adapter.synchronize(
            .push,
            workspace: harness.workspace,
            store: harness.store
        )

        let createdIdentity = harness.createdTaskIdentity()
        XCTAssertEqual(createdIdentity.externalID, harness.expectedCreatedExternalID)

        harness.publishRemoteUpdate()
        try await harness.adapter.synchronize(
            .incremental,
            workspace: harness.workspace,
            store: harness.store
        )

        XCTAssertTrue(harness.hasRemoteUpdate())

        harness.completeTask()
        try await harness.adapter.synchronize(
            .push,
            workspace: harness.workspace,
            store: harness.store
        )

        XCTAssertTrue(harness.isComplete())

        harness.deleteTask()
        try await harness.adapter.synchronize(
            .push,
            workspace: harness.workspace,
            store: harness.store
        )

        XCTAssertEqual(harness.archivedTaskIDs(), [createdIdentity.externalID])
        XCTAssertEqual(try harness.localTaskCount(), 0)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        try makeInMemoryStore().context
    }

    private func makeInMemoryStore() throws -> (container: ModelContainer, context: ModelContext) {
        let schema = Schema([
            TaskItem.self,
            ProjectItem.self,
            UserSession.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, ModelContext(container))
    }
}

private final class AlwaysFailingTaskProviderAdapter: TaskProviderAdapter {
    enum Failure: Error { case offline }

    let providerIdentity = TaskProviderIdentity.finallyServer
    let capabilities: Set<TaskProviderCapability> = [.createTasks, .updateTasks]
    private(set) var synchronizeCallCount = 0

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
        synchronizeCallCount += 1
        throw Failure.offline
    }
}

private final class RecordingTaskProviderAdapter: TaskProviderAdapter {
    let providerIdentity = TaskProviderIdentity.finallyServer
    let capabilities: Set<TaskProviderCapability> = [.createTasks, .updateTasks]
    private(set) var workspaceIDs: [String] = []

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
        guard let workspace else { throw TaskProviderAdapterError.workspaceRequired }
        workspaceIDs.append(workspace.workspaceId)
    }
}

private final class BlockingTaskProviderAdapter: TaskProviderAdapter {
    let providerIdentity = TaskProviderIdentity.finallyServer
    let capabilities: Set<TaskProviderCapability> = [.createTasks, .updateTasks]
    private let state = BlockingTaskProviderState()

    var callCount: Int {
        get async { await state.callCount }
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
        await state.block()
    }

    func waitUntilStarted() async {
        await state.waitUntilStarted()
    }

    func release() async {
        await state.release()
    }
}

/// Stands in for a provider push that reads its dirty list once, at the moment it starts.
private final class DirtyDrainingTaskProviderAdapter: TaskProviderAdapter {
    let providerIdentity = TaskProviderIdentity.finallyServer
    let capabilities: Set<TaskProviderCapability> = [.createTasks, .updateTasks]
    private(set) var observedDirtyTitles: [[String]] = []
    private let gate = DirtyDrainingGate()

    var arrivals: Int {
        get async { await gate.arrivals }
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
        let dirtyTasks = try store.fetch(FetchDescriptor<TaskItem>()).filter(\.isDirty)
        observedDirtyTitles.append(dirtyTasks.map(\.title).sorted())
        await gate.arrive()
        dirtyTasks.forEach { $0.isDirty = false }
        try store.save()
    }

    func waitUntilFirstArrival() async {
        await gate.waitUntilFirstArrival()
    }

    func open() async {
        await gate.open()
    }
}

private actor DirtyDrainingGate {
    private(set) var arrivals = 0
    private var isOpen = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func arrive() async {
        arrivals += 1
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilFirstArrival() async {
        if arrivals > 0 { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        isOpen = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor BlockingTaskProviderState {
    private(set) var callCount = 0
    private var isReleased = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func block() async {
        callCount += 1
        startedContinuations.forEach { $0.resume() }
        startedContinuations.removeAll()
        // Latching the release lets a surplus provider call finish so its count fails the test.
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        if callCount > 0 { return }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }
}

private struct TaskProviderLifecycleHarness<Adapter: TaskProviderAdapter> {
    let adapter: Adapter
    let workspace: Adapter.WorkspaceState
    let store: Adapter.LocalStore
    let createDraft: () throws -> Void
    let createdTaskIdentity: () -> ProviderTaskIdentity
    let expectedCreatedExternalID: String
    let publishRemoteUpdate: () -> Void
    let hasRemoteUpdate: () -> Bool
    let completeTask: () -> Void
    let isComplete: () -> Bool
    let deleteTask: () -> Void
    let archivedTaskIDs: () -> [String]
    let localTaskCount: () throws -> Int
}
