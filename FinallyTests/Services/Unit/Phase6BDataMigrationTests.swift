import XCTest
import SwiftData
@testable import Finally

@MainActor
final class Phase6BDataMigrationTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, ReminderItem.self, UserSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "phase6b.remindersMigrated")
        UserDefaults.standard.removeObject(forKey: "phase6b.fieldMigrationDone")
        super.tearDown()
    }

    func testMigrateLegacyFields_CopiesStartDateToTargetDate() throws {
        let ctx = try makeContext()
        let task = TaskItem(notionPageId: "t-1", title: "Legacy")
        task.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(task)
        try ctx.save()

        DataMigrationService.runIfNeeded(modelContext: ctx)

        XCTAssertEqual(task.targetDate, task.startDate)
    }

    func testMigrateReminderItems_ConvertsLegacyRowsToJSON() throws {
        let ctx = try makeContext()
        let task = TaskItem(notionPageId: "t-2", title: "Reminders")
        ctx.insert(task)

        let legacy = ReminderItem(intervalSeconds: 3600, label: "1 hour before", taskNotionPageId: task.notionPageId)
        legacy.task = task
        ctx.insert(legacy)
        try ctx.save()

        DataMigrationService.runIfNeeded(modelContext: ctx)

        XCTAssertFalse(task.taskReminders.isEmpty)
        let remaining = try ctx.fetch(FetchDescriptor<ReminderItem>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testLocalOnlySubtasks_FindsLegacySubtasksAwaitingPromotion() throws {
        let ctx = try makeContext()
        let parent = TaskItem(notionPageId: "parent", title: "Parent")
        let sub = TaskItem(notionPageId: "sub", title: "Local sub")
        sub.parentId = parent.notionPageId
        sub.isLocalOnly = true
        ctx.insert(parent)
        ctx.insert(sub)
        try ctx.save()

        let pending = DataMigrationService.localOnlySubtasks(in: ctx)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.notionPageId, "sub")
    }
}
