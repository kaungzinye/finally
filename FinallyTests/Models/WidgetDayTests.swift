import XCTest
@testable import Finally

final class WidgetDayTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Friday 16 October 2026, 15:00 UTC.
    private var now: Date { at(day: 16, hour: 15) }

    func testTheWidgetListsTodayInTheTodayTabsOrder() throws {
        let workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Notion", providerIdentity: .notion)
        let passport = task("Renew the passport", deadline: at(day: 15))
        let brief = task("Draft the brief", deadline: at(day: 16))
        let launch = task("Prepare the launch", scheduled: at(day: 16))
        let slides = subtask("Draft the slides", of: launch, suggested: at(day: 16))
        let release = task("Ship the release", deadline: at(day: 17), workspace: "server-workspace")
        let invoice = task("Send the invoice", deadline: at(day: 16))
        let plants = task("Water the plants", scheduled: at(day: 16))
        let dentist = task("Book the dentist", scheduled: at(day: 14))
        let rent = task("Pay the rent", scheduled: at(day: 16))
        rent.status = .done
        let contract = task("Review the contract", scheduled: at(day: 17))
        let tasks = [passport, brief, launch, slides, release, invoice, plants, dentist, rent, contract]
        let focus = DailyFocus(day: at(day: 16), storageWorkspaceID: "notion-workspace")
        focus.picks = [brief.dailyFocusPick, launch.dailyFocusPick, release.dailyFocusPick]

        let day = WidgetDay(
            snapshot: WidgetSnapshot(tasks: tasks, focus: focus, workspace: workspace, at: now, calendar: calendar),
            at: now,
            calendar: calendar
        )

        let expected = [
            "Draft the brief", "Draft the slides", "Ship the release",
            "Renew the passport", "Send the invoice", "Water the plants", "Book the dentist",
        ]
        XCTAssertEqual(day.today.map(\.title), expected)
        let todayTab = focus.executionPicks(among: tasks).compactMap(\.task)
            + focus.otherTasks(among: tasks.scoped(to: workspace), at: now, calendar: calendar).map(\.task)
        XCTAssertEqual(todayTab.map(\.title), expected)
    }

    func testPicksFromAnEarlierDayAreNotTodaysFocus() {
        let snapshot = WidgetSnapshot(focusDay: at(day: 15), focusLimit: 3, focusPickCount: 1, tasks: [
            widgetTask("Draft the brief", scheduled: at(day: 15), focusPosition: 1),
        ])

        let day = WidgetDay(snapshot: snapshot, at: now, calendar: calendar)

        XCTAssertEqual(day.picks, [])
        XCTAssertEqual(day.today.map(\.title), ["Draft the brief"])
    }

    func testTheFocusWidgetListsOpenPicksUnderTheFocusLimit() {
        let snapshot = WidgetSnapshot(focusDay: at(day: 16), focusLimit: 3, focusPickCount: 3, tasks: [
            widgetTask("Water the plants", scheduled: at(day: 16), focusPosition: 3),
            widgetTask("Draft the brief", deadline: at(day: 16), status: .done, focusPosition: 1),
            widgetTask("Ship the release", deadline: at(day: 17), focusPosition: 2),
            widgetTask("Send the invoice", deadline: at(day: 16)),
        ])

        let day = WidgetDay(snapshot: snapshot, at: now, calendar: calendar)

        XCTAssertEqual(day.focusHeading, "3 things to do")
        XCTAssertEqual(day.openPicks.map(\.title), ["Ship the release", "Water the plants"])
    }

    func testTheNowWidgetShowsTheFirstOpenPickAndItsPlace() {
        let snapshot = WidgetSnapshot(focusDay: at(day: 16), focusLimit: 3, focusPickCount: 3, tasks: [
            widgetTask("Draft the brief", deadline: at(day: 16), status: .done, focusPosition: 1),
            widgetTask("Ship the release", deadline: at(day: 17), focusPosition: 2),
            widgetTask("Water the plants", scheduled: at(day: 16), focusPosition: 3),
        ])

        let day = WidgetDay(snapshot: snapshot, at: now, calendar: calendar)

        XCTAssertEqual(day.nowPick?.title, "Ship the release")
        XCTAssertEqual(day.nowPickPlace, "2 of 3")
    }

    func testAOnePickFocusReadsOneThingToDo() {
        let snapshot = WidgetSnapshot(focusDay: at(day: 16), focusLimit: 1, focusPickCount: 0, tasks: [])

        let day = WidgetDay(snapshot: snapshot, at: now, calendar: calendar)

        XCTAssertEqual(day.focusHeading, "1 thing to do")
        XCTAssertNil(day.nowPick)
        XCTAssertNil(day.nowPickPlace)
    }

    func testComingUpHoldsTheNextSevenDaysByDateThenPriorityThenTitle() {
        var subtask = widgetTask("Draft the slides")
        subtask.isSubtask = true
        subtask.suggestedDate = at(day: 17)
        let snapshot = WidgetSnapshot(focusDay: nil, focusLimit: 3, focusPickCount: 0, tasks: [
            widgetTask("Review the contract", scheduled: at(day: 17)),
            widgetTask("Call the bank", deadline: at(day: 18), priority: .medium),
            widgetTask("Plan the trip", scheduled: at(day: 23)),
            widgetTask("Read the novel", scheduled: at(day: 24)),
            widgetTask("Send the invoice", deadline: at(day: 16)),
            widgetTask("Fix the bike", scheduled: at(day: 17), priority: .urgent),
            widgetTask("Plan the move", scheduled: at(day: 17), deadline: at(day: 30)),
            widgetTask("Pay the rent", scheduled: at(day: 17), status: .done),
            subtask,
        ])

        let day = WidgetDay(snapshot: snapshot, at: now, calendar: calendar)

        XCTAssertEqual(day.comingUp.map(\.title), [
            "Fix the bike", "Plan the move", "Review the contract", "Call the bank", "Plan the trip",
        ])
    }

    func testTheTodayWidgetFollowsTodayWithComingUpWhenRoomRemains() {
        let day = WidgetDay(snapshot: snapshot(today: 2, comingUp: 5), at: now, calendar: calendar)

        let layout = day.todayWidgetLayout(rows: 6)

        XCTAssertEqual(layout.today.map(\.title), ["Today 1", "Today 2"])
        XCTAssertEqual(layout.moreCount, 0)
        XCTAssertEqual(layout.comingUp.map(\.title), ["Coming 1", "Coming 2", "Coming 3"])
    }

    func testTheTodayWidgetEndsWithMoreWhenTodayOverflows() {
        let day = WidgetDay(snapshot: snapshot(today: 8, comingUp: 2), at: now, calendar: calendar)

        let layout = day.todayWidgetLayout(rows: 6)

        XCTAssertEqual(layout.today.map(\.title), ["Today 1", "Today 2", "Today 3", "Today 4", "Today 5"])
        XCTAssertEqual(layout.moreCount, 3)
        XCTAssertEqual(layout.comingUp, [])
    }

    func testTheTodayWidgetLeavesOutComingUpWithoutRoomForARow() {
        let day = WidgetDay(snapshot: snapshot(today: 5, comingUp: 2), at: now, calendar: calendar)

        let layout = day.todayWidgetLayout(rows: 6)

        XCTAssertEqual(layout.today.count, 5)
        XCTAssertEqual(layout.moreCount, 0)
        XCTAssertEqual(layout.comingUp, [])
    }

    func testTheRingDrawsOneSectionPerTodayTaskWithPicksFirstAndFinishedTasksFilled() {
        let snapshot = WidgetSnapshot(focusDay: at(day: 16), focusLimit: 3, focusPickCount: 2, tasks: [
            widgetTask("Water the plants", scheduled: at(day: 16)),
            widgetTask("Pay the rent", scheduled: at(day: 16), status: .done),
            widgetTask("Ship the release", deadline: at(day: 17), focusPosition: 2),
            widgetTask("Renew the passport", deadline: at(day: 15)),
            widgetTask("Book the dentist", scheduled: at(day: 14), status: .done),
            widgetTask("Send the invoice", deadline: at(day: 15), status: .done),
            widgetTask("Draft the brief", deadline: at(day: 16), status: .done, focusPosition: 1),
            widgetTask("Review the contract", scheduled: at(day: 17)),
        ])

        let day = WidgetDay(snapshot: snapshot, at: now, calendar: calendar)

        XCTAssertEqual(day.ringSections, [
            RingSection(isFocus: true, isDone: true),
            RingSection(isFocus: true, isDone: false),
            RingSection(isFocus: false, isDone: false),
            RingSection(isFocus: false, isDone: false),
            RingSection(isFocus: false, isDone: true),
        ])
    }

    // MARK: - Helpers

    /// Today tasks scheduled today and coming-up tasks scheduled tomorrow, numbered in title order.
    private func snapshot(today: Int, comingUp: Int) -> WidgetSnapshot {
        WidgetSnapshot(
            focusDay: nil,
            focusLimit: 3,
            focusPickCount: 0,
            tasks: (0..<today).map { widgetTask("Today \($0 + 1)", scheduled: at(day: 16)) }
                + (0..<comingUp).map { widgetTask("Coming \($0 + 1)", scheduled: at(day: 17)) }
        )
    }

    private func at(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func widgetTask(
        _ title: String,
        scheduled: Date? = nil,
        deadline: Date? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus = .notStarted,
        focusPosition: Int? = nil
    ) -> WidgetTask {
        WidgetTask(
            providerWorkspaceID: "notion-workspace", externalTaskID: title, title: title, priority: priority,
            status: status, scheduledDay: scheduled, deadline: deadline, focusPosition: focusPosition
        )
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
        workspace: String = "notion-workspace"
    ) -> TaskItem {
        let task = TaskItem(externalTaskID: title, title: title)
        task.providerWorkspaceId = workspace
        task.scheduledDay = scheduled
        task.deadline = deadline
        return task
    }
}
