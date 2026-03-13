import XCTest
import SwiftData
@testable import Finally

final class SyncServiceNotionMappingIntegrationTests: XCTestCase {
    func testFullSync_MapsTaskFields_FromNotionPageShape() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let mappings = PropertyMappings(
            taskTitleProperty: "Name",
            taskStatusProperty: "Status",
            taskDueDateProperty: "Due Date",
            taskPriorityProperty: "Priority",
            taskTagsProperty: "Tags",
            taskProjectProperty: "Project",
            taskRecurrenceProperty: "Recurrence",
            projectTitleProperty: "Name"
        )

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.projectsDatabaseId = "projects-db"
        session.propertyMappings = mappings
        context.insert(session)

        mock.queryAllPagesResult["projects-db"] = [
            NotionTestFactory.page(
                id: "proj-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "Home")]
                    )
                ]
            )
        ]
        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "Pay electricity")]
                    ),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "In Progress"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-21"),
                    "Priority": NotionTestFactory.propertyValue(type: "select", selectName: "High"),
                    "Tags": NotionTestFactory.propertyValue(type: "multi_select", multiSelectNames: ["Bills", "Home"]),
                    "Project": NotionTestFactory.propertyValue(type: "relation", relationIds: ["proj-1"]),
                    "Recurrence": NotionTestFactory.propertyValue(type: "select", selectName: "Monthly"),
                ]
            )
        ]

        try await syncService.fullSync(session: session, modelContext: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.title, "Pay electricity")
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.tags, ["Bills", "Home"])
        XCTAssertEqual(task.recurrence, .monthly)
        XCTAssertEqual(task.project?.notionPageId, "proj-1")
        XCTAssertNotNil(task.dueDate)
    }

    func testFullSync_WhenStatusNameUnknown_DefaultsSafelyToNotStarted() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.propertyMappings = PropertyMappings()
        context.insert(session)

        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "Unexpected status task")]
                    ),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "Blocked"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-21"),
                ]
            )
        ]

        try await syncService.fullSync(session: session, modelContext: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.status, .notStarted)
    }

    func testFullSync_WhenDueDateIsISODateTime_ParsesAndWhenNull_ClearsExistingDueDate() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.propertyMappings = PropertyMappings()
        context.insert(session)

        // First sync with full ISO timestamp due date
        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "Timezone check")]
                    ),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "Not Started"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-21T15:45:00.000Z"),
                ]
            )
        ]
        try await syncService.fullSync(session: session, modelContext: context)
        var task = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertNotNil(task.dueDate)

        // Next sync returns null date: due date should clear
        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(
                        type: "title",
                        title: [NotionRichText(plainText: "Timezone check")]
                    ),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "Not Started"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: nil),
                ]
            )
        ]
        try await syncService.fullSync(session: session, modelContext: context)
        task = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertNil(task.dueDate)
    }

    func testFullSync_WhenProjectRelationHasMultipleAndThenEmpty_UsesFirstThenClears() async throws {
        let mock = MockNotionAPIClient()
        let syncService = SyncService(api: mock)
        let context = try makeInMemoryContext()

        let session = UserSession(workspaceId: "ws-1", workspaceName: "Workspace")
        session.tasksDatabaseId = "tasks-db"
        session.projectsDatabaseId = "projects-db"
        session.propertyMappings = PropertyMappings()
        context.insert(session)

        mock.queryAllPagesResult["projects-db"] = [
            NotionTestFactory.page(
                id: "proj-1",
                properties: ["Name": NotionTestFactory.propertyValue(type: "title", title: [NotionRichText(plainText: "Alpha")])]
            ),
            NotionTestFactory.page(
                id: "proj-2",
                properties: ["Name": NotionTestFactory.propertyValue(type: "title", title: [NotionRichText(plainText: "Beta")])]
            ),
        ]
        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(type: "title", title: [NotionRichText(plainText: "Relation test")]),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "Not Started"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-21"),
                    "Project": NotionTestFactory.propertyValue(type: "relation", relationIds: ["proj-1", "proj-2"]),
                ]
            )
        ]
        try await syncService.fullSync(session: session, modelContext: context)
        var task = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(task.project?.notionPageId, "proj-1")

        mock.queryAllPagesResult["tasks-db"] = [
            NotionTestFactory.page(
                id: "task-1",
                properties: [
                    "Name": NotionTestFactory.propertyValue(type: "title", title: [NotionRichText(plainText: "Relation test")]),
                    "Status": NotionTestFactory.propertyValue(type: "status", statusName: "Not Started"),
                    "Due Date": NotionTestFactory.propertyValue(type: "date", dateStart: "2026-03-21"),
                    "Project": NotionTestFactory.propertyValue(type: "relation", relationIds: []),
                ]
            )
        ]
        try await syncService.fullSync(session: session, modelContext: context)
        task = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertNil(task.project)
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
