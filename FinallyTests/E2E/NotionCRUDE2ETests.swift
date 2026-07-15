import XCTest
import SwiftData
@testable import Finally

final class NotionCRUDE2ETests: NotionE2ETestCase {

    // MARK: - CREATE

    func testCreate_LocalToNotion_CreatesPageWithCorrectTitle() async throws {
        let task = try await pushLocalTask(title: "E2E Create Test")

        XCTAssertFalse(task.externalTaskID.isEmpty, "externalTaskID should be set after push")
        XCTAssertFalse(task.isDirty, "isDirty should be false after successful push")
        XCTAssertNotNil(task.lastSyncedAt)

        // Verify the page exists in Notion
        let pages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: nil, sorts: nil)
        let found = pages.first { $0.id == task.externalTaskID }
        XCTAssertNotNil(found, "Page should exist in Notion after push")
    }

    // MARK: - READ

    func testRead_NotionToLocal_CreatesLocalTaskItem() async throws {
        // Create a page directly via API
        let mappings = session.propertyMappings
        let props: [String: Any] = [
            mappings.taskTitleProperty: ["title": [["text": ["content": "E2E Read Test"]]]],
            mappings.taskStatusProperty: ["status": ["name": "Not Started"]]
        ]
        let page = try await api.createPage(databaseId: session.tasksDatabaseId, properties: props)
        createdPageIds.append(page.id)

        // Full sync should pull it into local context
        try await syncService.fullSync(session: session, modelContext: modelContext)

        let task = try fetchTask(externalTaskID: page.id)
        XCTAssertNotNil(task, "Task should exist locally after fullSync")
        XCTAssertEqual(task?.title, "E2E Read Test")
    }

    // MARK: - UPDATE local → remote

    func testUpdate_LocalToRemote_UpdatesNotionPage() async throws {
        let task = try await pushLocalTask(title: "E2E Update Initial")

        // Modify locally and push again
        task.title = "E2E Update Modified"
        task.isDirty = true
        try modelContext.save()
        try await syncService.pushDirtyChanges(session: session, modelContext: modelContext)

        // Verify Notion reflects the update
        let pages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: nil, sorts: nil)
        let found = pages.first { $0.id == task.externalTaskID }
        XCTAssertNotNil(found)

        let mappings = session.propertyMappings
        let titleTexts = found?.properties[mappings.taskTitleProperty]?.title
        let remoteTitle = titleTexts?.map(\.plainText).joined() ?? ""
        XCTAssertEqual(remoteTitle, "E2E Update Modified")
    }

    // MARK: - UPDATE remote → local

    func testUpdate_RemoteToLocal_IncrementalSyncUpdatesLocalTask() async throws {
        let task = try await pushLocalTask(title: "E2E Remote Update")

        // Edit the page in Notion directly
        let mappings = session.propertyMappings
        let updatedProps: [String: Any] = [
            mappings.taskTitleProperty: ["title": [["text": ["content": "E2E Remote Updated Title"]]]]
        ]
        _ = try await api.updatePage(pageId: task.externalTaskID, properties: updatedProps)

        // Reset lastFullSyncAt to allow incremental sync to see the edit
        session.lastFullSyncAt = Date.distantPast
        try modelContext.save()

        try await syncService.fullSync(session: session, modelContext: modelContext)

        let updated = try fetchTask(externalTaskID: task.externalTaskID)
        XCTAssertEqual(updated?.title, "E2E Remote Updated Title")
    }

    // MARK: - CONFLICT local wins

    func testConflict_LocalWins_DirtyTaskPreservedDuringSyncThenPushed() async throws {
        let task = try await pushLocalTask(title: "E2E Conflict Initial")

        // Mark local dirty with a different title
        task.title = "E2E Local Version"
        task.isDirty = true
        try modelContext.save()

        // Also edit remotely to simulate conflict
        let mappings = session.propertyMappings
        let remoteProps: [String: Any] = [
            mappings.taskTitleProperty: ["title": [["text": ["content": "E2E Remote Version"]]]]
        ]
        _ = try await api.updatePage(pageId: task.externalTaskID, properties: remoteProps)

        // incrementalSync should skip the dirty task (local wins)
        session.lastFullSyncAt = Date.distantPast
        try modelContext.save()
        try await syncService.fullSync(session: session, modelContext: modelContext)

        let afterSync = try XCTUnwrap(try fetchTask(externalTaskID: task.externalTaskID))
        XCTAssertEqual(afterSync.title, "E2E Local Version", "Local version should be preserved during sync")
        XCTAssertTrue(afterSync.isDirty, "isDirty should remain true until pushed")

        // Now push — Notion should receive the local version
        try await syncService.pushDirtyChanges(session: session, modelContext: modelContext)

        let pages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: nil, sorts: nil)
        let found = pages.first { $0.id == task.externalTaskID }
        let remoteTitle = found?.properties[mappings.taskTitleProperty]?.title?.map(\.plainText).joined() ?? ""
        XCTAssertEqual(remoteTitle, "E2E Local Version", "Notion should have local version after push")
    }

    // MARK: - DIRTY FLAG preserved

    func testDirtyFlag_PreservedDuringIncrementalSync() async throws {
        let task = try await pushLocalTask(title: "E2E Dirty Preserved")
        let originalTitle = "E2E Dirty Local Edit"
        task.title = originalTitle
        task.isDirty = true
        try modelContext.save()

        session.lastFullSyncAt = Date.distantPast
        try modelContext.save()
        try await syncService.fullSync(session: session, modelContext: modelContext)

        let afterSync = try XCTUnwrap(try fetchTask(externalTaskID: task.externalTaskID))
        XCTAssertTrue(afterSync.isDirty, "isDirty should remain true after sync skips the task")
        XCTAssertEqual(afterSync.title, originalTitle, "Title should not be overwritten by sync")
    }

    // MARK: - DELETE stale removal

    func testDelete_ArchivedInNotion_RemovedLocallyAfterFullSync() async throws {
        let task = try await pushLocalTask(title: "E2E Delete Stale")
        let pageId = task.externalTaskID

        // Archive in Notion (removes it from query results)
        try await api.archivePage(pageId: pageId)
        // Don't add to createdPageIds cleanup since it's already archived

        try await syncService.fullSync(session: session, modelContext: modelContext)

        let afterSync = try fetchTask(externalTaskID: pageId)
        XCTAssertNil(afterSync, "Task should be deleted locally after being archived in Notion")
    }

    // MARK: - DELETE preserves dirty (Bug 4 regression)

    func testDelete_DirtyTaskPreservedWhenArchivedInNotion() async throws {
        let task = try await pushLocalTask(title: "E2E Dirty Not Deleted")
        let pageId = task.externalTaskID

        // Archive in Notion
        try await api.archivePage(pageId: pageId)

        // Mark local task dirty before fullSync
        task.isDirty = true
        task.title = "E2E Dirty Preserved After Archive"
        try modelContext.save()

        try await syncService.fullSync(session: session, modelContext: modelContext)

        let afterSync = try fetchTask(externalTaskID: pageId)
        XCTAssertNotNil(afterSync, "Dirty task should NOT be deleted even if archived in Notion")
        XCTAssertTrue(afterSync?.isDirty == true)
    }

    // MARK: - FULL SYNC multiple tasks

    func testFullSync_MultipleTasks_AllSyncedLocally() async throws {
        var pageIds: [String] = []
        let mappings = session.propertyMappings

        for i in 1...5 {
            let props: [String: Any] = [
                mappings.taskTitleProperty: ["title": [["text": ["content": "E2E Bulk Task \(i)"]]]],
                mappings.taskStatusProperty: ["status": ["name": "Not Started"]]
            ]
            let page = try await api.createPage(databaseId: session.tasksDatabaseId, properties: props)
            pageIds.append(page.id)
            createdPageIds.append(page.id)
        }

        try await syncService.fullSync(session: session, modelContext: modelContext)

        for pageId in pageIds {
            let task = try fetchTask(externalTaskID: pageId)
            XCTAssertNotNil(task, "Task \(pageId) should exist locally after fullSync")
        }
    }

    // MARK: - INCREMENTAL SYNC

    func testIncrementalSync_OnlyUpdatesEditedTask() async throws {
        let mappings = session.propertyMappings
        var pageIds: [String] = []

        for i in 1...3 {
            let props: [String: Any] = [
                mappings.taskTitleProperty: ["title": [["text": ["content": "E2E Inc Task \(i)"]]]],
                mappings.taskStatusProperty: ["status": ["name": "Not Started"]]
            ]
            let page = try await api.createPage(databaseId: session.tasksDatabaseId, properties: props)
            pageIds.append(page.id)
            createdPageIds.append(page.id)
        }

        try await syncService.fullSync(session: session, modelContext: modelContext)

        // Edit only the first task in Notion
        let editedProps: [String: Any] = [
            mappings.taskTitleProperty: ["title": [["text": ["content": "E2E Inc Task 1 Edited"]]]]
        ]
        _ = try await api.updatePage(pageId: pageIds[0], properties: editedProps)

        try await syncService.incrementalSync(session: session, modelContext: modelContext)

        let editedTask = try fetchTask(externalTaskID: pageIds[0])
        XCTAssertEqual(editedTask?.title, "E2E Inc Task 1 Edited")

        let untouched2 = try fetchTask(externalTaskID: pageIds[1])
        XCTAssertEqual(untouched2?.title, "E2E Inc Task 2")

        let untouched3 = try fetchTask(externalTaskID: pageIds[2])
        XCTAssertEqual(untouched3?.title, "E2E Inc Task 3")
    }
}
