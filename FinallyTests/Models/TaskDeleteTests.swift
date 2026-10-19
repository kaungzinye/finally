import SwiftData
import XCTest
@testable import Finally

final class TaskDeleteTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_788_000_000))

    func testDeletingATaskMarksItForItsProviderAndDropsItsDailyFocusPicks() throws {
        let store = try makeInMemoryContext()
        let task = TaskItem(externalTaskID: "s1", title: "Renew the passport")
        task.providerWorkspaceId = "server-workspace"
        let other = TaskItem(externalTaskID: "n1", title: "Draft the brief")
        other.providerWorkspaceId = "notion-workspace"
        let today = DailyFocus(day: day, storageWorkspaceID: "server-workspace")
        try today.add(other.dailyFocusPick)
        try today.add(task.dailyFocusPick)
        let yesterday = DailyFocus(day: day.addingTimeInterval(-86_400), storageWorkspaceID: "notion-workspace")
        try yesterday.add(task.dailyFocusPick)
        let untouched = DailyFocus(day: day, storageWorkspaceID: "notion-workspace")
        try untouched.add(other.dailyFocusPick)
        [task, other].forEach(store.insert)
        [today, yesterday, untouched].forEach(store.insert)

        let changed = try task.delete(in: store)

        XCTAssertTrue(task.isDeleted)
        XCTAssertTrue(task.isDirty)
        XCTAssertFalse(other.isDeleted)
        XCTAssertEqual(today.picks, [other.dailyFocusPick])
        XCTAssertTrue(yesterday.picks.isEmpty)
        XCTAssertEqual(untouched.picks, [other.dailyFocusPick])
        XCTAssertEqual(Set(changed.map(\.persistentModelID)), [today.persistentModelID, yesterday.persistentModelID])
    }

    func testDeletingATaskOutsideDailyFocusChangesNoDailyFocus() throws {
        let store = try makeInMemoryContext()
        let task = TaskItem(externalTaskID: "n2", title: "Read the novel")
        task.providerWorkspaceId = "notion-workspace"
        store.insert(task)
        store.insert(DailyFocus(day: day, storageWorkspaceID: "notion-workspace"))

        XCTAssertTrue(try task.delete(in: store).isEmpty)
        XCTAssertTrue(task.isDeleted)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }
}
