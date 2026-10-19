import XCTest
@testable import Finally

final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Friday 16 October 2026, 15:00 UTC.
    private var now: Date { at(day: 16, hour: 15) }

    func testTheSnapshotCarriesEachDatedTaskOfTheSelectedWorkspace() {
        let invoice = task("Send the invoice", deadline: at(day: 16, hour: 17), deadlineHasTime: true, priority: .high)
        invoice.status = .inProgress
        let plants = task("Water the plants", scheduled: at(day: 18))
        let novel = task("Read the novel")
        let elsewhere = task("Ship the release", scheduled: at(day: 16), workspace: "server-workspace")
        let removed = task("Old idea", deadline: at(day: 16))
        removed.isDeleted = true

        let snapshot = WidgetSnapshot(
            tasks: [invoice, plants, novel, elsewhere, removed], focus: nil, workspace: notion, at: now, calendar: calendar
        )

        XCTAssertEqual(snapshot.tasks.sorted { $0.title < $1.title }, [
            WidgetTask(
                providerWorkspaceID: "notion-workspace", externalTaskID: "Send the invoice", title: "Send the invoice",
                priority: .high, status: .inProgress, scheduledDay: nil, deadline: at(day: 16, hour: 17), deadlineHasTime: true
            ),
            WidgetTask(
                providerWorkspaceID: "notion-workspace", externalTaskID: "Water the plants", title: "Water the plants",
                priority: nil, status: .notStarted, scheduledDay: at(day: 18), deadline: nil
            ),
        ])
    }

    func testTheSnapshotPlacesEachDailyFocusPickInPickOrder() throws {
        let brief = task("Draft the brief", deadline: at(day: 16))
        let launch = task("Prepare the launch", scheduled: at(day: 16))
        let slides = subtask("Draft the slides", of: launch, suggested: at(day: 16))
        let release = task("Ship the release", deadline: at(day: 17), workspace: "server-workspace")
        let rent = task("Pay the rent", scheduled: at(day: 16))
        rent.status = .done
        let focus = DailyFocus(day: at(day: 16), focusLimit: 5, storageWorkspaceID: "notion-workspace")
        focus.picks = [
            brief.dailyFocusPick,
            launch.dailyFocusPick,
            release.dailyFocusPick,
            rent.dailyFocusPick,
            DailyFocusPick(providerWorkspaceID: "notion-workspace", externalTaskID: "removed"),
        ]

        let snapshot = WidgetSnapshot(
            tasks: [brief, launch, slides, release, rent], focus: focus, workspace: notion, at: now, calendar: calendar
        )

        let titles = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0.title) })
        XCTAssertEqual(snapshot.focusPlaces.map { place in [String(place.position)] + place.taskIDs.map { titles[$0] ?? $0 } }, [
            ["1", "Draft the brief"],
            ["2", "Draft the slides", "Prepare the launch"],
            ["3", "Ship the release"],
            ["4", "Pay the rent"],
        ])
        XCTAssertEqual(snapshot.focusDay, at(day: 16))
        XCTAssertEqual(snapshot.focusLimit, 5)
        XCTAssertEqual(snapshot.focusPickCount, 5)
    }

    func testTheSnapshotCarriesWhetherTheUserConfirmedTheDailyFocus() {
        let brief = task("Draft the brief", deadline: at(day: 16))
        let focus = DailyFocus(day: at(day: 16), storageWorkspaceID: "notion-workspace")
        focus.picks = [brief.dailyFocusPick]

        let proposed = WidgetSnapshot(tasks: [brief], focus: focus, workspace: notion, at: now, calendar: calendar)
        focus.confirm()
        let confirmed = WidgetSnapshot(tasks: [brief], focus: focus, workspace: notion, at: now, calendar: calendar)

        XCTAssertFalse(proposed.isFocusConfirmed)
        XCTAssertTrue(confirmed.isFocusConfirmed)
    }

    func testTheSnapshotKeepsTasksFinishedOnTheirDay() {
        let rent = task("Pay the rent", scheduled: at(day: 16))
        rent.status = .done
        let invoice = task("Send the invoice", deadline: at(day: 16))
        invoice.status = .done
        let dentist = task("Book the dentist", scheduled: at(day: 14))
        dentist.status = .done

        let snapshot = WidgetSnapshot(tasks: [rent, invoice, dentist], focus: nil, workspace: notion, at: now, calendar: calendar)

        XCTAssertEqual(Set(snapshot.tasks.map(\.title)), ["Pay the rent", "Send the invoice"])
    }

    func testAWidgetRowOpensItsTaskInItsOwnWorkspace() {
        let task = WidgetTask(
            providerWorkspaceID: "server-workspace", externalTaskID: "42", title: "Ship the release",
            priority: nil, status: .notStarted, scheduledDay: nil, deadline: nil
        )
        let router = NavigationRouter()

        router.handleURL(task.url)

        XCTAssertEqual(router.deepLinkTaskId, "42")
        XCTAssertEqual(router.deepLinkWorkspaceId, "server-workspace")
    }

    func testTheConfirmLinkOpensTheTodayTab() {
        let router = NavigationRouter()
        router.selectedTab = .tasks

        router.handleURL(AppConstants.todayURL)

        XCTAssertEqual(router.selectedTab, .today)
    }

    func testTheSnapshotSurvivesAppGroupStorage() {
        let storage = makeStorage()
        let snapshot = WidgetSnapshot(
            workspaceID: "notion-workspace",
            focusDay: at(day: 16),
            focusLimit: 3,
            focusPickCount: 2,
            isFocusConfirmed: true,
            focusPlaces: [WidgetFocusPlace(position: 1, taskIDs: ["notion-workspace:brief"])],
            tasks: [
                WidgetTask(
                    providerWorkspaceID: "notion-workspace", externalTaskID: "brief", title: "Draft the brief",
                    priority: .urgent, status: .notStarted, scheduledDay: at(day: 16), deadline: at(day: 17, hour: 9),
                    deadlineHasTime: true
                ),
                WidgetTask(
                    providerWorkspaceID: "notion-workspace", externalTaskID: "slides", title: "Draft the slides",
                    priority: nil, status: .done, scheduledDay: nil, deadline: nil,
                    isSubtask: true, suggestedDate: at(day: 16, hour: 11)
                ),
            ]
        )

        storage.snapshot = snapshot

        XCTAssertEqual(storage.snapshot, snapshot)
    }

    // MARK: - Helpers

    private let notion = UserSession(workspaceId: "notion-workspace", workspaceName: "Notion", providerIdentity: .notion)

    private func makeStorage() -> WidgetStorage {
        let suite = "WidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return WidgetStorage(defaults: defaults, completionsDirectory: FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory))
    }

    private func at(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func subtask(_ title: String, of parent: TaskItem, suggested: Date, index: Int = 0) -> TaskItem {
        let subtask = task(title, workspace: parent.providerWorkspaceId ?? "")
        subtask.parentId = parent.externalTaskID
        subtask.parent = parent
        subtask.sortIndex = index
        subtask.suggestedDate = suggested
        parent.subtasks.append(subtask)
        return subtask
    }

    private func task(
        _ title: String,
        scheduled: Date? = nil,
        deadline: Date? = nil,
        deadlineHasTime: Bool = false,
        priority: TaskPriority? = nil,
        workspace: String = "notion-workspace"
    ) -> TaskItem {
        let task = TaskItem(externalTaskID: title, title: title)
        task.providerWorkspaceId = workspace
        task.scheduledDay = scheduled
        task.deadline = deadline
        task.deadlineHasTime = deadlineHasTime
        task.priority = priority
        return task
    }
}
