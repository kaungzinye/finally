import XCTest
@testable import Finally

final class TaskDetailEditTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: value))!
    }

    func testEdit_TitleBecomesDirtyEdit() {
        let task = TaskItem(externalTaskID: "edit-1", title: "Draft")

        task.edit(calendar: calendar) { $0.title = "Draft the proposal" }

        XCTAssertEqual(task.title, "Draft the proposal")
        XCTAssertTrue(task.isDirty)
    }

    func testEdit_DeadlineBeforeScheduledDayMovesScheduledDayToDeadlineDay() {
        let task = TaskItem(externalTaskID: "edit-2", title: "Draft")
        task.scheduledDay = day(25)
        let deadline = day(20)

        task.edit(calendar: calendar) { $0.setDeadline(deadline, hasTime: false, defaults: .standard) }

        XCTAssertEqual(task.scheduledDay, day(20))
        XCTAssertTrue(task.isDirty)
    }

    func testEdit_ScheduledDayOnDeadlineDayStays() {
        let task = TaskItem(externalTaskID: "edit-3", title: "Draft")
        task.deadline = day(20)
        let scheduledDay = day(20)

        task.edit(calendar: calendar) { $0.scheduledDay = scheduledDay }

        XCTAssertEqual(task.scheduledDay, day(20))
        XCTAssertTrue(task.isDirty)
    }
}
