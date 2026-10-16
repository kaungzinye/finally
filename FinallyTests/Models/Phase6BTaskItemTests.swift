import XCTest
@testable import Finally

final class Phase6BTaskItemTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testScheduledDayAndDeadlineRemainIndependent() throws {
        let task = TaskItem(externalTaskID: "planning-terms", title: "Plan launch")
        let scheduledDay = makeDate(year: 2026, month: 9, day: 14)
        let deadline = makeDate(year: 2026, month: 9, day: 21)

        task.scheduledDay = scheduledDay
        task.deadline = deadline

        XCTAssertEqual(try XCTUnwrap(task.scheduledDay), scheduledDay)
        XCTAssertEqual(try XCTUnwrap(task.deadline), deadline)
    }

    func testValidateScheduledDay_MovesScheduledDayAfterDeadlineToDeadlineDay() {
        let task = TaskItem(externalTaskID: "t-1", title: "Task")
        task.deadline = makeDate(year: 2026, month: 6, day: 20)
        task.scheduledDay = makeDate(year: 2026, month: 6, day: 25)

        task.validateScheduledDay(calendar: calendar)

        XCTAssertEqual(task.scheduledDay, makeDate(year: 2026, month: 6, day: 20))
    }

    func testValidateScheduledDay_KeepsScheduledDayOnDeadlineDay() {
        let task = TaskItem(externalTaskID: "t-1b", title: "Task")
        task.deadline = makeDate(year: 2026, month: 6, day: 20)
        task.scheduledDay = makeDate(year: 2026, month: 6, day: 20)

        task.validateScheduledDay(calendar: calendar)

        XCTAssertEqual(task.scheduledDay, makeDate(year: 2026, month: 6, day: 20))
    }

    func testValidateScheduledDay_KeepsScheduledDayOnTimedDeadlineDay() {
        let task = TaskItem(externalTaskID: "t-1c", title: "Task")
        task.setDeadline(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9)),
            hasTime: true,
            defaults: .standard
        )
        task.scheduledDay = makeDate(year: 2026, month: 6, day: 20)

        task.validateScheduledDay(calendar: calendar)

        XCTAssertEqual(task.scheduledDay, makeDate(year: 2026, month: 6, day: 20))
    }

    func testIsInActiveWindow_RequiresScheduledDayAndDeadlineSpanningToday() {
        let task = TaskItem(externalTaskID: "t-2", title: "Task")
        let today = calendar.startOfDay(for: Date())
        task.scheduledDay = calendar.date(byAdding: .day, value: -2, to: today)
        task.deadline = calendar.date(byAdding: .day, value: 2, to: today)
        task.status = .notStarted

        XCTAssertTrue(task.isInActiveWindow)
    }

    func testComplete_RecurringObligationCarriesScheduledDayOffset() {
        let task = TaskItem(externalTaskID: "t-3", title: "Weekly")
        // Use a past deadline so recurrence advances to the next cycle.
        task.deadline = calendar.date(byAdding: .day, value: -1, to: Date())
        task.scheduledDay = calendar.date(byAdding: .day, value: -8, to: Date())
        task.recurrence = .weekly
        task.status = .inProgress

        let previousOffset = task.deadline!.timeIntervalSince(task.scheduledDay!)
        let recycled = task.complete()

        XCTAssertTrue(recycled)
        XCTAssertEqual(task.status, .notStarted)
        XCTAssertNotNil(task.deadline)
        XCTAssertNotNil(task.scheduledDay)
        XCTAssertTrue(task.scheduledDay! < task.deadline!)
        XCTAssertEqual(task.deadline!.timeIntervalSince(task.scheduledDay!), previousOffset, accuracy: 86400)
    }

    func testComplete_RecurringObligationResetsSubtasksToNotStarted() {
        let parent = TaskItem(externalTaskID: "parent", title: "Parent")
        parent.deadline = makeDate(year: 2026, month: 6, day: 20)
        parent.recurrence = .weekly

        let subtask = TaskItem(externalTaskID: "sub-1", title: "Sub")
        subtask.parentId = parent.externalTaskID
        subtask.parent = parent
        subtask.status = .done
        parent.subtasks = [subtask]

        _ = parent.complete()

        XCTAssertEqual(subtask.status, .notStarted)
    }

    func testTaskReminders_PersistsOnTaskItem() {
        let task = TaskItem(externalTaskID: "t-4", title: "Task")
        task.taskReminders = [
            TaskReminder.deadline(DeadlineReminder(offset: .hourBefore)),
            .exact(ExactReminder(at: Date(timeIntervalSince1970: 1_700_000_000))),
        ]

        XCTAssertEqual(task.taskReminders.count, 2)
        XCTAssertNotNil(task.remindersJSON)
        XCTAssertTrue(task.hasReminders)
    }

    func testDeadlineDemoFixture_ProvidesCompleteDeadlineScenario() throws {
        let referenceDate = makeDate(year: 2026, month: 6, day: 27)

        let task = DeadlineDemoFixture.makeTask(referenceDate: referenceDate, calendar: calendar)

        XCTAssertEqual(task.title, "Ship the project proposal")
        XCTAssertEqual(task.priority, .urgent)
        XCTAssertEqual(task.recurrence, .weekly)
        XCTAssertTrue(try XCTUnwrap(task.scheduledDay) < XCTUnwrap(task.deadline))
        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1)])
        XCTAssertEqual(task.subtasks.map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(task.subtasks.filter { $0.status == .done }.count, 1)
    }
}
