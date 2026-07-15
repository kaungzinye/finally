import SwiftData
import XCTest
@testable import Finally

final class TaskProviderContractTests: XCTestCase {
    func testProviderCoordinatorPushMakesLocalDraftProviderBacked() async throws {
        let mock = MockNotionAPIClient()
        let coordinator = TaskProviderCoordinator(adapter: SyncService(api: mock))
        let context = try makeInMemoryContext()
        let workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        workspace.tasksDatabaseId = "tasks-db"
        context.insert(workspace)
        let task = TaskItem(notionPageId: UUID().uuidString, title: "Review proposal")
        task.isDirty = true
        context.insert(task)
        try context.save()

        try await coordinator.synchronize(.push, workspace: workspace, store: context)

        XCTAssertEqual(task.notionPageId, "remote-1")
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
        let task = TaskItem(notionPageId: "notion-page", title: "Review proposal")

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
        let task = TaskItem(notionPageId: UUID().uuidString, title: "Review proposal")

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
        let schema = Schema([
            TaskItem.self,
            ProjectItem.self,
            UserSession.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
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
