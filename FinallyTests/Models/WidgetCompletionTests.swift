import SwiftData
import XCTest
@testable import Finally

final class WidgetCompletionTests: XCTestCase {
    func testCompletingFromAWidgetRecordsTheCompletionAndShowsTheTaskDone() {
        let storage = makeStorage()
        let today = Calendar.current.startOfDay(for: Date())
        storage.snapshot = WidgetSnapshot(workspaceID: "notion-workspace", focusDay: today, focusLimit: 3, focusPickCount: 2, isFocusConfirmed: true, focusPlaces: [place(1, "brief"), place(2, "release")], tasks: [
            widgetTask("brief", "Draft the brief"),
            widgetTask("release", "Ship the release"),
        ])

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "brief"))

        XCTAssertEqual(storage.pendingCompletions.map(\.completion), [
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
        focus.confirm()
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
        XCTAssertTrue(storage.pendingCompletions.isEmpty)
        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.openPicks.map(\.title), ["Ship the release"])
    }

    func testPublishingBeforeTheAppAppliesAWidgetCompletionKeepsTheTaskDone() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let brief = insertTask("brief", "Draft the brief", into: context)
        let release = insertTask("release", "Ship the release", into: context)
        let focus = DailyFocus(day: Calendar.current.startOfDay(for: Date()), storageWorkspaceID: "notion-workspace")
        focus.picks = [brief.dailyFocusPick, release.dailyFocusPick]
        focus.confirm()
        context.insert(focus)
        try context.save()
        try WidgetPublisher.publish(store: context, storage: storage)

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "brief"))
        try WidgetPublisher.publish(store: context, storage: storage)

        XCTAssertEqual(brief.status, .notStarted)
        XCTAssertEqual(storage.pendingCompletions.count, 1)
        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.openPicks.map(\.title), ["Ship the release"])
        XCTAssertEqual(day.ringSections.filter(\.isDone).count, 1)
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
        XCTAssertTrue(storage.pendingCompletions.isEmpty)
    }

    func testACompletionTheWidgetRecordsWhileTheAppAppliesStaysPending() {
        let app = makeStorage()
        let widget = WidgetStorage(defaults: app.defaults, completionsDirectory: app.completionsDirectory)
        app.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "brief"))

        let read = app.pendingCompletions
        widget.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "release"))
        app.removePendingCompletions(read)

        XCTAssertEqual(app.pendingCompletions.map(\.completion), [
            WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "release"),
        ])
    }

    func testRepeatedTapsCompleteARecurringObligationOnce() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let rent = insertTask("rent", "Pay the rent", into: context)
        let deadline = Calendar.current.startOfDay(for: Date().addingTimeInterval(10 * 86_400))
        rent.deadline = deadline
        rent.recurrence = .monthly
        try context.save()

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "rent"))
        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "rent"))
        try WidgetPublisher.applyPendingCompletions(store: context, storage: storage)

        XCTAssertEqual(rent.deadline, Calendar.current.date(byAdding: .month, value: 1, to: deadline))
        XCTAssertTrue(storage.pendingCompletions.isEmpty)
    }

    func testCompletingAPickedParentsStepFromAWidgetShowsItsNextStep() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let launch = try publishPickedParentWithSteps(into: context, storage: storage)

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "slides"))

        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.nowPick?.title, "Rehearse the talk")
        XCTAssertEqual(day.nowPickPlace, "1 of 1")
        XCTAssertEqual(launch.status, .notStarted)
    }

    func testCompletingAPickedParentsLastStepFromAWidgetShowsTheParent() throws {
        let storage = makeStorage()
        let context = try makeContext()
        try publishPickedParentWithSteps(into: context, storage: storage)

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "slides"))
        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "rehearse"))

        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.nowPick?.title, "Prepare the launch")
        XCTAssertEqual(day.nowPickPlace, "1 of 1")
    }

    func testCompletingALaterStepFirstLeavesTheCurrentStepInPlace() throws {
        let storage = makeStorage()
        let context = try makeContext()
        try publishPickedParentWithSteps(into: context, storage: storage)

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "rehearse"))
        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "slides"))

        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.nowPick?.title, "Prepare the launch")
    }

    func testAStepPickedBesideItsParentKeepsItsOwnPlace() throws {
        let storage = makeStorage()
        let context = try makeContext()
        try publishPickedParentWithSteps(into: context, storage: storage, alsoPicking: "rehearse")

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "slides"))

        var day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.nowPick?.title, "Rehearse the talk")
        XCTAssertEqual(day.nowPickPlace, "1 of 2")
        XCTAssertEqual(day.openPicks.map(\.title), ["Rehearse the talk"])
        XCTAssertEqual(day.ringSections, [RingSection(isFocus: true, isDone: false), RingSection(isFocus: true, isDone: false)])

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "rehearse"))

        day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.nowPick?.title, "Prepare the launch")
        XCTAssertEqual(day.nowPickPlace, "1 of 2")
        XCTAssertEqual(day.ringSections, [RingSection(isFocus: true, isDone: false), RingSection(isFocus: true, isDone: true)])
    }

    func testTheAppApplyingAStepCompletionShowsTheNextStep() throws {
        let storage = makeStorage()
        let context = try makeContext()
        try publishPickedParentWithSteps(into: context, storage: storage)

        storage.complete(WidgetCompletion(providerWorkspaceID: "notion-workspace", externalTaskID: "slides"))
        try WidgetPublisher.applyPendingCompletions(store: context, storage: storage)

        let day = WidgetDay(snapshot: storage.snapshot!, at: Date())
        XCTAssertEqual(day.nowPick?.title, "Rehearse the talk")
    }

    // MARK: - Helpers

    /// Publishes a Daily Focus whose one pick, "Prepare the launch", has two undated steps.
    @discardableResult
    private func publishPickedParentWithSteps(
        into context: ModelContext, storage: WidgetStorage, alsoPicking stepID: String? = nil
    ) throws -> TaskItem {
        let launch = insertTask("launch", "Prepare the launch", into: context)
        var picks = [launch.dailyFocusPick]
        for (index, (id, title)) in [("slides", "Draft the slides"), ("rehearse", "Rehearse the talk")].enumerated() {
            let step = TaskItem(externalTaskID: id, title: title)
            step.providerWorkspaceId = "notion-workspace"
            step.parentId = launch.externalTaskID
            step.parent = launch
            step.sortIndex = index
            context.insert(step)
            if id == stepID { picks.append(step.dailyFocusPick) }
        }
        let focus = DailyFocus(day: Calendar.current.startOfDay(for: Date()), storageWorkspaceID: "notion-workspace")
        focus.picks = picks
        focus.confirm()
        context.insert(focus)
        try context.save()
        try WidgetPublisher.publish(store: context, storage: storage)
        return launch
    }

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

    private func place(_ position: Int, _ externalTaskID: String) -> WidgetFocusPlace {
        WidgetFocusPlace(position: position, taskIDs: ["notion-workspace:\(externalTaskID)"])
    }

    private func widgetTask(_ id: String, _ title: String) -> WidgetTask {
        WidgetTask(
            providerWorkspaceID: "notion-workspace", externalTaskID: id, title: title, priority: nil,
            status: .notStarted, scheduledDay: Calendar.current.startOfDay(for: Date()), deadline: nil
        )
    }

    private func makeStorage() -> WidgetStorage {
        let suite = "WidgetCompletionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return WidgetStorage(defaults: defaults, completionsDirectory: directory)
    }
}
