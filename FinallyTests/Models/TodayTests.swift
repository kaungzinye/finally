import XCTest
@testable import Finally

final class TodayTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Friday 16 October 2026, 15:00 UTC.
    private var now: Date { at(day: 16, hour: 15) }

    func testTodayHoldsOpenTasksScheduledOrDueToday() {
        let scheduled = task("Water the plants", scheduled: at(day: 16))
        let due = task("Send the invoice", deadline: at(day: 16))
        let later = task("Plan the trip", scheduled: at(day: 17), deadline: at(day: 20))
        let unscheduled = task("Read the novel")
        let finished = task("Pay the rent", scheduled: at(day: 16))
        finished.status = .done
        let deleted = task("Old idea", deadline: at(day: 16))
        deleted.isDeleted = true

        let members = Today.members(of: [scheduled, due, later, unscheduled, finished, deleted], at: now, calendar: calendar)

        XCTAssertEqual(Set(members.map(\.task.title)), ["Water the plants", "Send the invoice"])
    }

    func testTodayListsOverdueThenDueTodayThenScheduledTodayThenMissedScheduledDays() {
        let missed = task("Book the dentist", scheduled: at(day: 14))
        let scheduled = task("Water the plants", scheduled: at(day: 16))
        let due = task("Send the invoice", deadline: at(day: 16))
        let overdue = task("Renew the passport", deadline: at(day: 15))

        let members = Today.members(of: [missed, scheduled, due, overdue], at: now, calendar: calendar)

        XCTAssertEqual(members.map(\.task.title), ["Renew the passport", "Send the invoice", "Water the plants", "Book the dentist"])
        XCTAssertEqual(members.map(\.reason), [.overdue, .dueToday, .scheduledToday, .missedScheduledDay])
    }

    func testTodayOrdersEachGroupByDateThenPriorityThenTitle() {
        let tasks = [
            task("Water the plants", scheduled: at(day: 16)),
            task("Call the bank", scheduled: at(day: 16), priority: .urgent),
            task("Answer the email", scheduled: at(day: 16)),
            task("File the receipts", deadline: at(day: 15)),
            task("Renew the passport", deadline: at(day: 12)),
            task("Book the dentist", scheduled: at(day: 15)),
            task("Fix the bike", scheduled: at(day: 13)),
            task("Ship the draft", deadline: at(day: 16, hour: 18), deadlineHasTime: true),
            task("Send the invoice", deadline: at(day: 16, hour: 17), deadlineHasTime: true),
        ]

        let members = Today.members(of: tasks, at: at(day: 16, hour: 9), calendar: calendar)

        XCTAssertEqual(members.map(\.task.title), [
            "Renew the passport", "File the receipts",
            "Send the invoice", "Ship the draft",
            "Call the bank", "Answer the email", "Water the plants",
            "Fix the bike", "Book the dentist",
        ])
    }

    func testADeadlineOutranksAMissedScheduledDay() {
        let due = task("Send the invoice", scheduled: at(day: 13), deadline: at(day: 16))

        XCTAssertEqual(Today.reason(for: due, at: now, calendar: calendar), .dueToday)
    }

    func testSubtasksDueByTheirSuggestedDateStandInForTheirParent() {
        let parent = task("Prepare the launch", scheduled: at(day: 16))
        let outline = subtask("Write the outline", of: parent, suggested: at(day: 14), index: 0)
        let slides = subtask("Draft the slides", of: parent, suggested: at(day: 16, hour: 11), index: 1)
        let rehearse = subtask("Rehearse the talk", of: parent, suggested: at(day: 17), index: 2)
        let finished = subtask("Book the room", of: parent, suggested: at(day: 13), index: 3)
        finished.status = .done

        let members = Today.members(of: [parent, outline, slides, rehearse, finished], at: now, calendar: calendar)

        XCTAssertEqual(members.map(\.task.title), ["Draft the slides", "Write the outline"])
        XCTAssertEqual(members.map(\.reason), [.scheduledToday, .scheduledToday])
    }

    func testAParentReturnsOnceEverySubtaskIsDone() {
        let parent = task("Prepare the launch", scheduled: at(day: 16))
        let outline = subtask("Write the outline", of: parent, suggested: at(day: 14), index: 0)
        outline.status = .done

        let members = Today.members(of: [parent, outline], at: now, calendar: calendar)

        XCTAssertEqual(members.map(\.task.title), ["Prepare the launch"])
    }

    func testMembershipRollsOverAtMidnight() {
        let scheduled = task("Water the plants", scheduled: at(day: 16))
        let due = task("Send the invoice", deadline: at(day: 16))
        let lastMinute = at(day: 16, hour: 23, minute: 59)
        let midnight = at(day: 17)

        XCTAssertEqual(Today.reason(for: scheduled, at: lastMinute, calendar: calendar), .scheduledToday)
        XCTAssertEqual(Today.reason(for: due, at: lastMinute, calendar: calendar), .dueToday)
        XCTAssertEqual(Today.reason(for: scheduled, at: midnight, calendar: calendar), .missedScheduledDay)
        XCTAssertEqual(Today.reason(for: due, at: midnight, calendar: calendar), .overdue)
    }

    func testATimedDeadlineTurnsOverdueOnceItsTimePasses() {
        let due = task("Ship the draft", deadline: at(day: 16, hour: 18), deadlineHasTime: true)

        XCTAssertEqual(Today.reason(for: due, at: at(day: 16, hour: 18), calendar: calendar), .dueToday)
        XCTAssertEqual(Today.reason(for: due, at: at(day: 16, hour: 18, minute: 1), calendar: calendar), .overdue)
    }

    func testOtherTasksLeaveOutEveryPickAndTheStepStandingInForOne() throws {
        let brief = task("Draft the brief", deadline: at(day: 16))
        let invoice = task("Send the invoice", deadline: at(day: 16))
        let plants = task("Water the plants", scheduled: at(day: 16))
        let launch = task("Prepare the launch", scheduled: at(day: 16))
        let slides = subtask("Draft the slides", of: launch, suggested: at(day: 16), index: 0)
        let focus = DailyFocus(day: at(day: 16))
        try focus.add(brief.dailyFocusPick)
        try focus.add(launch.dailyFocusPick)

        let others = focus.otherTasks(among: [brief, invoice, plants, launch, slides], at: now, calendar: calendar)

        XCTAssertEqual(others.map(\.task.title), ["Send the invoice", "Water the plants"])
    }

    func testATaskRowCallsAPassedTimedDeadlineOverdue() {
        let passed = task("Ship the draft", deadline: Date().addingTimeInterval(-60), deadlineHasTime: true)
        let upcoming = task("Send the invoice", deadline: Date().addingTimeInterval(3_600), deadlineHasTime: true)

        XCTAssertTrue(passed.isOverdue)
        XCTAssertFalse(upcoming.isOverdue)
    }

    // MARK: - Helpers

    private func subtask(_ title: String, of parent: TaskItem, suggested: Date, index: Int) -> TaskItem {
        let subtask = task(title)
        subtask.parentId = parent.externalTaskID
        subtask.parent = parent
        subtask.sortIndex = index
        subtask.suggestedDate = suggested
        parent.subtasks.append(subtask)
        return subtask
    }

    private func at(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func task(
        _ title: String,
        scheduled: Date? = nil,
        deadline: Date? = nil,
        deadlineHasTime: Bool = false,
        priority: TaskPriority? = nil
    ) -> TaskItem {
        let task = TaskItem(externalTaskID: title, title: title)
        task.providerWorkspaceId = "notion-workspace"
        task.scheduledDay = scheduled
        task.deadline = deadline
        task.deadlineHasTime = deadlineHasTime
        task.priority = priority
        return task
    }
}
