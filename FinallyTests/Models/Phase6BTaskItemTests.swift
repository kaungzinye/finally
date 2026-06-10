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

    func testValidateTargetDate_KeepsTargetEarlierThanDue() {
        let task = TaskItem(notionPageId: "t-1", title: "Task")
        task.dueDate = makeDate(year: 2026, month: 6, day: 20)
        task.targetDate = makeDate(year: 2026, month: 6, day: 25)

        task.validateTargetDate()

        XCTAssertNotNil(task.targetDate)
        XCTAssertTrue(task.targetDate! < task.dueDate!)
    }

    func testIsInActiveWindow_RequiresTargetAndDueSpanningToday() {
        let task = TaskItem(notionPageId: "t-2", title: "Task")
        let today = calendar.startOfDay(for: Date())
        task.targetDate = calendar.date(byAdding: .day, value: -2, to: today)
        task.dueDate = calendar.date(byAdding: .day, value: 2, to: today)
        task.status = .notStarted

        XCTAssertTrue(task.isInActiveWindow)
    }

    func testComplete_RecurringTaskCarriesTargetDateOffset() {
        let task = TaskItem(notionPageId: "t-3", title: "Weekly")
        // Use a past due date so recurrence advances to the next cycle.
        task.dueDate = calendar.date(byAdding: .day, value: -1, to: Date())
        task.targetDate = calendar.date(byAdding: .day, value: -8, to: Date())
        task.recurrence = .weekly
        task.status = .inProgress

        let previousOffset = task.dueDate!.timeIntervalSince(task.targetDate!)
        let recycled = task.complete()

        XCTAssertTrue(recycled)
        XCTAssertEqual(task.status, .notStarted)
        XCTAssertNotNil(task.dueDate)
        XCTAssertNotNil(task.targetDate)
        XCTAssertTrue(task.targetDate! < task.dueDate!)
        XCTAssertEqual(task.dueDate!.timeIntervalSince(task.targetDate!), previousOffset, accuracy: 86400)
    }

    func testComplete_RecurringTaskResetsSubtasksToNotStarted() {
        let parent = TaskItem(notionPageId: "parent", title: "Parent")
        parent.dueDate = makeDate(year: 2026, month: 6, day: 20)
        parent.recurrence = .weekly

        let subtask = TaskItem(notionPageId: "sub-1", title: "Sub")
        subtask.parentId = parent.notionPageId
        subtask.parent = parent
        subtask.status = .done
        parent.subtasks = [subtask]

        _ = parent.complete()

        XCTAssertEqual(subtask.status, .notStarted)
    }

    func testTaskReminders_PersistsOnTaskItem() {
        let task = TaskItem(notionPageId: "t-4", title: "Task")
        task.taskReminders = [
            TaskReminder.presetThirtyMinutesBeforeDue(),
            .explicitDate(ExplicitDateReminder(dateTime: Date(timeIntervalSince1970: 1_700_000_000))),
        ]

        XCTAssertEqual(task.taskReminders.count, 2)
        XCTAssertNotNil(task.remindersJSON)
        XCTAssertTrue(task.hasReminders)
    }
}
