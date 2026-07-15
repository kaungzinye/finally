import SwiftData
import XCTest
@testable import Finally

final class TaskProviderContractTests: XCTestCase {
    func testUnsyncedCreateIsDurableBeforeThrowingProviderPush() async throws {
        let (container, context) = try makeInMemoryStore()
        let adapter = AlwaysFailingTaskProviderAdapter()
        let coordinator = TaskProviderCoordinator(adapter: adapter)
        let workspace = UserSession(workspaceId: "workspace", workspaceName: "Workspace")
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
        let workspace = UserSession(workspaceId: "workspace", workspaceName: "Workspace")
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
        let workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        workspace.tasksDatabaseId = "tasks-db"
        context.insert(workspace)
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Review proposal")
        task.isDirty = true
        context.insert(task)
        try context.save()

        try await coordinator.synchronize(.push, workspace: workspace, store: context)

        XCTAssertEqual(task.externalTaskID, "remote-1")
        XCTAssertFalse(task.isDirty)
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

    func testNotionAdapterMapsStoredWorkspaceAndTaskIntoProviderNeutralIdentities() {
        let adapter = SyncService(api: MockNotionAPIClient())
        let session = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
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
        let session = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        session.tasksDatabaseId = "tasks-db"
        context.insert(session)
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Review proposal")

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
        let session = UserSession(workspaceId: "server-workspace", workspaceName: "Personal")
        session.providerIdentity = .finallyServer
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
