import XCTest
@testable import Finally

final class TaskStatusCycleTests: XCTestCase {
    func testCycleStatus_MovesNotStartedToInProgress() {
        let task = TaskItem(externalTaskID: "cycle-1", title: "Draft")

        task.cycleStatus()

        XCTAssertEqual(task.status, .inProgress)
        XCTAssertTrue(task.isDirty)
    }

    func testCycleStatus_MovesInProgressToComplete() {
        let task = TaskItem(externalTaskID: "cycle-2", title: "Draft")
        task.status = .inProgress

        task.cycleStatus()

        XCTAssertEqual(task.status, .done)
        XCTAssertTrue(task.isDirty)
    }

    func testCycleStatus_MovesCompleteToNotStarted() {
        let task = TaskItem(externalTaskID: "cycle-3", title: "Draft")
        task.status = .done

        task.cycleStatus()

        XCTAssertEqual(task.status, .notStarted)
        XCTAssertTrue(task.isDirty)
    }

    func testCycleStatus_CompletingRecurringObligationStartsItsNextCycle() {
        let task = TaskItem(externalTaskID: "cycle-4", title: "Water the plants")
        let deadline = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        task.deadline = deadline
        task.recurrence = .weekly
        task.status = .inProgress

        task.cycleStatus()

        XCTAssertEqual(task.status, .notStarted)
        XCTAssertGreaterThan(try XCTUnwrap(task.deadline), deadline)
    }

    // MARK: - Board moves

    func testMove_SetsTheDroppedColumnsStatusAsADirtyEdit() {
        let task = TaskItem(externalTaskID: "move-1", title: "Draft")

        task.move(to: .done)

        XCTAssertEqual(task.status, .done)
        XCTAssertTrue(task.isDirty)
    }

    func testMove_DroppingOnItsOwnColumnLeavesTheTaskUntouched() {
        let task = TaskItem(externalTaskID: "move-2", title: "Draft")
        task.status = .inProgress

        task.move(to: .inProgress)

        XCTAssertEqual(task.status, .inProgress)
        XCTAssertFalse(task.isDirty)
    }

    func testMove_CompletingRecurringObligationStartsItsNextCycle() {
        let task = TaskItem(externalTaskID: "move-3", title: "Water the plants")
        let deadline = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        task.deadline = deadline
        task.recurrence = .weekly

        let recycled = task.move(to: .done)

        XCTAssertTrue(recycled)
        XCTAssertEqual(task.status, .notStarted)
        XCTAssertGreaterThan(try XCTUnwrap(task.deadline), deadline)
        XCTAssertTrue(task.isDirty)
    }
}
