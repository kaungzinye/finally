import XCTest
import SwiftData
@testable import Finally

final class BackendDataFlowIntegrationTests: XCTestCase {
    func testSchemaValidationFlow_WhenSchemaDegrades_ReportsMissingThenTypeMismatch() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "status"),
                "Due Date": NotionTestFactory.schema(type: "date"),
            ]),
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Due Date": NotionTestFactory.schema(type: "date"),
            ]),
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "status"),
                "Due Date": NotionTestFactory.schema(type: "rich_text"),
            ]),
        ]

        let validator = SchemaValidator(api: mock)

        let (first, _) = try await validator.validateTasksDatabase(id: "tasks-db")
        XCTAssertTrue(first.isValid)

        let (second, _) = try await validator.validateTasksDatabase(id: "tasks-db")
        XCTAssertFalse(second.isValid)
        XCTAssertTrue(second.issues.contains { $0.propertyName == "Status" && $0.expectedType == "status" })

        let (third, _) = try await validator.validateTasksDatabase(id: "tasks-db")
        XCTAssertFalse(third.isValid)
        XCTAssertTrue(third.issues.contains { $0.propertyName == "Due Date" && $0.expectedType == "date" })
    }

    func testPushDirtyChangesFlow_CreatesThenUpdatesAndSendsRequiredProperties() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        context.insert(session)

        let task = TaskItem(notionPageId: UUID().uuidString, title: "Recurring bill")
        task.status = .notStarted
        task.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        task.recurrence = .weekly
        task.isDirty = true
        task.lastSyncedAt = nil
        context.insert(task)
        try context.save()

        try await syncService.pushDirtyChanges(session: session, modelContext: context)

        XCTAssertEqual(mock.createdPages.count, 1)
        XCTAssertEqual(mock.updatedPages.count, 0)
        XCTAssertFalse(task.isDirty)
        XCTAssertEqual(task.notionPageId, "remote-1")
        XCTAssertNotNil(task.lastSyncedAt)

        // Simulate recurring completion update (status reset + due date in one PATCH payload)
        task.status = .notStarted
        task.dueDate = Date(timeIntervalSince1970: 1_700_604_800)
        task.isDirty = true

        try await syncService.pushDirtyChanges(session: session, modelContext: context)

        XCTAssertEqual(mock.updatedPages.count, 1)
        let properties = try XCTUnwrap(mock.updatedPages.first?.properties)
        XCTAssertNotNil(properties[session.propertyMappings.taskStatusProperty])
        XCTAssertNotNil(properties[session.propertyMappings.taskDueDateProperty])
    }

    func testPushDirtyChanges_WhenNoTasksDatabaseId_LeavesUnsyncedTaskDirty() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = ""
        context.insert(session)

        let task = TaskItem(notionPageId: UUID().uuidString, title: "Offline draft")
        task.isDirty = true
        task.lastSyncedAt = nil
        context.insert(task)
        try context.save()

        try await syncService.pushDirtyChanges(session: session, modelContext: context)

        XCTAssertEqual(mock.createdPages.count, 0)
        XCTAssertEqual(mock.updatedPages.count, 0)
        XCTAssertTrue(task.isDirty)
        XCTAssertNil(task.lastSyncedAt)
    }

    func testIncrementalSync_WhenNotionTaskChanges_UpdatesLocalTaskFields() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.lastFullSyncAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(session)

        let local = TaskItem(notionPageId: "task-1", title: "Old title")
        local.status = .notStarted
        local.lastSyncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(local)
        try context.save()

        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                lastEditedTime: "2026-03-13T12:00:00.000Z",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "New title")]
                    ),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "In Progress"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-30"),
                ]
            )
        ]

        try await syncService.incrementalSync(session: session, modelContext: context)

        let refreshed = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(refreshed.title, "New title")
        XCTAssertEqual(refreshed.status, .inProgress)
        XCTAssertNotNil(refreshed.dueDate)
        XCTAssertFalse(mock.queryCalls.isEmpty)
        XCTAssertNotNil(mock.queryCalls.first?.filter)
        XCTAssertNotNil(session.lastFullSyncAt)
    }

    func testFullSync_WhenTaskRemovedFromNotion_DeletesLocalTask() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        context.insert(session)

        let staleTask = TaskItem(notionPageId: "task-stale", title: "Should disappear")
        context.insert(staleTask)
        try context.save()

        mock.queryAllPagesResult["tasks-db"] = []

        try await syncService.fullSync(session: session, modelContext: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(tasks.isEmpty)
    }

    func testIncrementalSync_WhenTaskMissingRemotely_DoesNotDeleteLocalUntilFullSync() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.lastFullSyncAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(session)

        let local = TaskItem(notionPageId: "task-1", title: "Local stays on incremental")
        context.insert(local)
        try context.save()

        mock.queryAllPagesResult["tasks-db"] = []

        try await syncService.incrementalSync(session: session, modelContext: context)
        var tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 1)

        try await syncService.fullSync(session: session, modelContext: context)
        tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(tasks.isEmpty)
    }

    func testIncrementalSync_WhenLocalTaskIsDirty_RemoteEditDoesNotOverwriteLocal() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.lastFullSyncAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(session)

        let local = TaskItem(notionPageId: "task-1", title: "Local draft title")
        local.status = .inProgress
        local.isDirty = true
        local.lastSyncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(local)
        try context.save()

        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "Remote changed title")]
                    ),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "Done"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-22"),
                ]
            )
        ]

        try await syncService.incrementalSync(session: session, modelContext: context)
        let taskAfterPull = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(taskAfterPull.title, "Local draft title")
        XCTAssertEqual(taskAfterPull.status, .inProgress)
        XCTAssertTrue(taskAfterPull.isDirty)

        try await syncService.pushDirtyChanges(session: session, modelContext: context)
        XCTAssertEqual(mock.updatedPages.count, 1)
        let patched = try XCTUnwrap(mock.updatedPages.first?.properties)
        let titlePayload = patched[session.propertyMappings.taskTitleProperty] as? [String: Any]
        let titleArray = titlePayload?["title"] as? [[String: Any]]
        let textObj = titleArray?.first?["text"] as? [String: Any]
        XCTAssertEqual(textObj?["content"] as? String, "Local draft title")
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            TaskItem.self,
            ProjectItem.self,
            ReminderItem.self,
            UserSession.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
