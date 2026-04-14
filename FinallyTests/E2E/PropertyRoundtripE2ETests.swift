import XCTest
import SwiftData
@testable import Finally

/// Tests that each TaskItem property survives a full local → push → Notion → fullSync roundtrip.
final class PropertyRoundtripE2ETests: NotionE2ETestCase {

    // MARK: - Title

    func testRoundtrip_Title_PlainText() async throws {
        let task = try await pushLocalTask(title: "Simple roundtrip title")
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.title, "Simple roundtrip title")
    }

    func testRoundtrip_Title_SpecialCharsAndEmoji() async throws {
        let title = "Roundtrip: éàü & symbols 🎉 <test>"
        let task = try await pushLocalTask(title: title)
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.title, title)
    }

    func testRoundtrip_Title_LongString() async throws {
        let title = String(repeating: "Long title word ", count: 20).trimmingCharacters(in: .whitespaces)
        let task = try await pushLocalTask(title: title)
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.title, title)
    }

    // MARK: - Status

    func testRoundtrip_Status_NotStarted() async throws {
        let task = try await pushLocalTask(title: "Status NotStarted") { t in
            t.status = .notStarted
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.status, .notStarted)
    }

    func testRoundtrip_Status_InProgress() async throws {
        let task = try await pushLocalTask(title: "Status InProgress") { t in
            t.status = .inProgress
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.status, .inProgress)
    }

    func testRoundtrip_Status_Done() async throws {
        let task = try await pushLocalTask(title: "Status Done") { t in
            t.status = .done
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.status, .done)
    }

    // MARK: - Due Date

    func testRoundtrip_DueDate_DateOnly() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dueDate = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let task = try await pushLocalTask(title: "Due Date roundtrip") { t in
            t.dueDate = dueDate
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))

        let syncedComponents = cal.dateComponents([.year, .month, .day], from: try XCTUnwrap(synced.dueDate))
        XCTAssertEqual(syncedComponents.year, 2026)
        XCTAssertEqual(syncedComponents.month, 6)
        XCTAssertEqual(syncedComponents.day, 15)
    }

    func testRoundtrip_DueDateRange_StartAndEnd() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let startDate = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let endDate = cal.date(from: DateComponents(year: 2026, month: 7, day: 7))!

        let task = try await pushLocalTask(title: "Date Range roundtrip") { t in
            t.startDate = startDate
            t.dueDate = endDate
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))

        let startComponents = cal.dateComponents([.year, .month, .day], from: try XCTUnwrap(synced.startDate))
        let endComponents = cal.dateComponents([.year, .month, .day], from: try XCTUnwrap(synced.dueDate))
        XCTAssertEqual(startComponents.day, 1)
        XCTAssertEqual(endComponents.day, 7)
    }

    // MARK: - Priority

    func testRoundtrip_Priority_AllLevels() async throws {
        let cases: [(TaskPriority?, String)] = [
            (.urgent, "Urgent"),
            (.high, "High"),
            (.medium, "Medium"),
            (.low, "Low"),
        ]
        for (priority, label) in cases {
            let task = try await pushLocalTask(title: "Priority \(label)") { t in
                t.priority = priority
            }
            try await syncService.fullSync(session: session, modelContext: modelContext)
            let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
            XCTAssertEqual(synced.priority, priority, "Priority \(label) should roundtrip")
        }
    }

    func testRoundtrip_Priority_Nil() async throws {
        let task = try await pushLocalTask(title: "Priority nil") { t in
            t.priority = nil
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertNil(synced.priority)
    }

    // MARK: - Tags

    func testRoundtrip_Tags_MultipleTags() async throws {
        let task = try await pushLocalTask(title: "Tags roundtrip") { t in
            t.tags = ["Work", "Urgent", "Review"]
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(Set(synced.tags), Set(["Work", "Urgent", "Review"]))
    }

    func testRoundtrip_Tags_ColorsPreserved() async throws {
        let task = try await pushLocalTask(title: "Tag colors roundtrip") { t in
            t.tags = ["Alpha", "Beta"]
        }
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        // Colors are assigned by Notion; just verify they are non-empty strings
        XCTAssertEqual(synced.tagColors.count, synced.tags.count)
        XCTAssertTrue(synced.tagColors.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Recurrence

    func testRoundtrip_Recurrence_AllPresets() async throws {
        let cases: [Recurrence] = [.none, .daily, .weekly, .monthly, .yearly]
        for recurrence in cases {
            let task = try await pushLocalTask(title: "Recurrence \(recurrence.rawValue)") { t in
                t.recurrence = recurrence
            }
            try await syncService.fullSync(session: session, modelContext: modelContext)
            let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
            XCTAssertEqual(synced.recurrence, recurrence, "Recurrence \(recurrence.rawValue) should roundtrip")
        }
    }

    // MARK: - Project Relation

    func testRoundtrip_ProjectRelation() async throws {
        try XCTSkipIf(E2EConfig.projectsDatabaseId == nil, "Skipping — NOTION_E2E_PROJECTS_DB not set")

        // Create a project page in Notion
        let projMappings = session.propertyMappings
        let projProps: [String: Any] = [
            projMappings.projectTitleProperty: ["title": [["text": ["content": "E2E Test Project"]]]]
        ]
        let projectPage = try await api.createPage(
            databaseId: session.projectsDatabaseId,
            properties: projProps
        )
        createdPageIds.append(projectPage.id)

        // Full sync to bring the project into local context
        try await syncService.fullSync(session: session, modelContext: modelContext)

        let projectId = projectPage.id
        let projectDescriptor = FetchDescriptor<ProjectItem>(
            predicate: #Predicate<ProjectItem> { $0.notionPageId == projectId }
        )
        let localProject = try XCTUnwrap(try modelContext.fetch(projectDescriptor).first)

        // Push a task linked to that project
        let task = try await pushLocalTask(title: "Task With Project") { t in
            t.project = localProject
        }

        // Full sync again and verify the relation roundtrips
        try await syncService.fullSync(session: session, modelContext: modelContext)
        let synced = try XCTUnwrap(try fetchTask(notionPageId: task.notionPageId))
        XCTAssertEqual(synced.project?.notionPageId, projectPage.id)
    }
}
