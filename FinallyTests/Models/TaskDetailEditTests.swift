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

    func testReschedule_PastTheDeadlineStopsOnTheDeadlineDay() {
        let task = TaskItem(externalTaskID: "late", title: "Ship the release notes")
        task.deadline = day(12)

        task.reschedule(to: day(15), calendar: calendar)

        XCTAssertEqual(task.scheduledDay, day(12))
        XCTAssertTrue(task.isDirty)
    }

    func testReschedule_BeforeTheDeadlineKeepsTheChosenDay() {
        let task = TaskItem(externalTaskID: "early", title: "Ship the release notes")
        task.deadline = day(12)

        task.reschedule(to: day(9), calendar: calendar)

        XCTAssertEqual(task.scheduledDay, day(9))
    }

    func testToggleCompletion_TickedStepBecomesDirtyEdit() {
        let step = TaskItem(externalTaskID: "step", title: "Draft the outline")

        step.toggleCompletion()

        XCTAssertEqual(step.status, .done)
        XCTAssertTrue(step.isDirty)
    }

    func testToggleCompletion_UntickedStepBecomesDirtyEdit() {
        let step = TaskItem(externalTaskID: "step", title: "Draft the outline")
        step.status = .done

        step.toggleCompletion()

        XCTAssertEqual(step.status, .notStarted)
        XCTAssertTrue(step.isDirty)
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

    func testEdit_TitleLeavesScheduledDayAfterDeadlineAlone() {
        let task = TaskItem(externalTaskID: "edit-4", title: "Draft")
        task.deadline = day(20)
        task.scheduledDay = day(25)

        task.edit(calendar: calendar) { $0.title = "Draft the proposal" }

        XCTAssertEqual(task.scheduledDay, day(25))
        XCTAssertEqual(task.deadline, day(20))
        XCTAssertTrue(task.isDirty)
    }

    func testEdit_PriorityLeavesScheduledDayAfterDeadlineAlone() {
        let task = TaskItem(externalTaskID: "edit-5", title: "Draft")
        task.deadline = day(20)
        task.scheduledDay = day(25)

        task.edit(calendar: calendar) { $0.priority = .high }

        XCTAssertEqual(task.scheduledDay, day(25))
    }

    func testEdit_DeadlineEditClampsScheduledDayAfterIt() {
        let task = TaskItem(externalTaskID: "edit-6", title: "Draft")
        task.deadline = day(20)
        task.scheduledDay = day(25)
        let deadline = day(22)

        task.edit(calendar: calendar) { $0.setDeadline(deadline, hasTime: false, defaults: .standard) }

        XCTAssertEqual(task.scheduledDay, day(22))
    }

    func testEdit_ScheduledDayOnDeadlineDayStays() {
        let task = TaskItem(externalTaskID: "edit-3", title: "Draft")
        task.deadline = day(20)
        let scheduledDay = day(20)

        task.edit(calendar: calendar) { $0.scheduledDay = scheduledDay }

        XCTAssertEqual(task.scheduledDay, day(20))
        XCTAssertTrue(task.isDirty)
    }

    func testPendingEdits_CleanParentWithAnAddedStepSubmitsTheStep() {
        let parent = TaskItem(externalTaskID: "parent", title: "Prepare the launch")
        let step = TaskItem(externalTaskID: "step", title: "Draft the slides")
        step.parentId = parent.externalTaskID
        step.parent = parent
        step.isDirty = true
        parent.subtasks.append(step)
        let clean = TaskItem(externalTaskID: "clean", title: "Book the venue")
        clean.parentId = parent.externalTaskID
        clean.parent = parent
        parent.subtasks.append(clean)

        XCTAssertEqual(parent.pendingEdits.map(\.externalTaskID), ["step"])
    }

    func testPendingEdits_DirtyParentSubmitsWithItsDirtySteps() {
        let parent = TaskItem(externalTaskID: "parent", title: "Prepare the launch")
        parent.edit(calendar: calendar) { $0.title = "Prepare the product launch" }
        let step = TaskItem(externalTaskID: "step", title: "Draft the slides")
        step.parentId = parent.externalTaskID
        step.parent = parent
        step.isDirty = true
        parent.subtasks.append(step)

        XCTAssertEqual(parent.pendingEdits.map(\.externalTaskID), ["parent", "step"])
    }

    func testPendingEdits_CleanTaskSubmitsNothing() {
        let task = TaskItem(externalTaskID: "clean", title: "Draft")

        XCTAssertEqual(task.pendingEdits, [])
    }
}
