import SwiftData
import XCTest
@testable import Finally

final class WidgetCompletionTests: XCTestCase {
    func testCompletingFromAWidgetRecordsTheCompletionAndShowsTheTaskDone() {
        let storage = makeStorage()
        let today = Calendar.current.startOfDay(for: Date())
        storage.snapshot = WidgetSnapshot(focusDay: today, focusLimit: 3, focusPickCount: 2, tasks: [
            widgetTask("brief", "Draft the brief", focusPosition: 1),
            widgetTask("release", "Ship the release", focusPosition: 2),
        ])

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "brief"))

        XCTAssertEqual(storage.pendingCompletions, [
            WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "brief"),
        ])
        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.openPicks.map(\.title), ["Ship the release"])
        XCTAssertEqual(day.ringSections.filter(\.isDone).count, 1)
    }

    func testTheAppAppliesWidgetCompletionsAsDirtyEditsAndClearsThem() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let brief = insertTask("brief", "Draft the brief", into: context)
        let release = insertTask("release", "Ship the release", into: context)
        let focus = DailyFocus(day: Calendar.current.startOfDay(for: Date()), storageWorkspaceID: "notion-workspace")
        focus.picks = [brief.dailyFocusPick, release.dailyFocusPick]
        context.insert(focus)
        try context.save()
        try WidgetPublisher.publish(store: context, storage: storage)

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "brief"))
        let applied = try WidgetPublisher.applyPendingCompletions(store: context, storage: storage)

        XCTAssertEqual(applied.map(\.title), ["Draft the brief"])
        XCTAssertEqual(brief.status, .done)
        XCTAssertTrue(brief.isDirty)
        XCTAssertEqual(release.status, .notStarted)
        XCTAssertFalse(release.isDirty)
        XCTAssertEqual(storage.pendingCompletions, [])
        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.openPicks.map(\.title), ["Ship the release"])
    }

    func testACompletionForAFinishedOrMissingTaskChangesNothing() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let rent = insertTask("rent", "Pay the rent", into: context)
        rent.status = .done
        try context.save()

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "rent"))
        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "gone"))
        let applied = try WidgetPublisher.applyPendingCompletions(store: context, storage: storage)

        XCTAssertEqual(applied, [])
        XCTAssertFalse(rent.isDirty)
        XCTAssertEqual(storage.pendingCompletions, [])
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        addTeardownBlock { _ = container }
        let workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Notion", providerIdentity: .notion)
        workspace.isSelected = true
        context.insert(workspace)
        return context
    }

    private func insertTask(_ id: String, _ title: String, into context: ModelContext) -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = "notion-workspace"
        task.scheduledDay = Calendar.current.startOfDay(for: Date())
        context.insert(task)
        return task
    }

    private func widgetTask(_ id: String, _ title: String, focusPosition: Int? = nil) -> WidgetTask {
        WidgetTask(
            providerWorkspaceID: "notion-workspace", externalTaskID: id, title: title, priority: nil,
            status: .notStarted, scheduledDay: Calendar.current.startOfDay(for: Date()), deadline: nil,
            focusPosition: focusPosition
        )
    }

    private func makeStorage() -> WidgetStorage {
        let suite = "WidgetCompletionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return WidgetStorage(defaults: defaults)
    }
}
