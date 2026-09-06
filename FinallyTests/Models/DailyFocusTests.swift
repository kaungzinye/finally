import SwiftData
import XCTest
@testable import Finally

final class DailyFocusTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_788_000_000))

    func testDailyFocusRefusesPicksBeyondFocusLimit() throws {
        let focus = DailyFocus(day: day)
        XCTAssertEqual(focus.focusLimit, 3)

        try focus.add(pick("write-brief"))
        try focus.add(pick("call-bank"))
        try focus.add(pick("ship-proposal"))

        XCTAssertThrowsError(try focus.add(pick("clean-desk"))) { error in
            XCTAssertEqual(error as? DailyFocusError, .full(limit: 3))
        }
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["write-brief", "call-bank", "ship-proposal"])
    }

    func testDailyFocusKeepsPickOrderAcrossRemoveAndReorder() throws {
        let focus = DailyFocus(day: day, focusLimit: 5)
        try focus.add(pick("a"))
        try focus.add(pick("b"))
        try focus.add(pick("c"))
        try focus.add(pick("d"))

        focus.remove(pick("b"))
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["a", "c", "d"])

        focus.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["d", "a", "c"])
    }

    func testDailyFocusIgnoresAPickItAlreadyHolds() throws {
        let focus = DailyFocus(day: day)
        try focus.add(pick("a"))
        try focus.add(pick("a"))
        XCTAssertEqual(focus.picks.count, 1)
    }

    func testConfirmingDailyFocusFlipsStateOnTheSameRecord() throws {
        let focus = DailyFocus(day: day)
        try focus.add(pick("a"))
        XCTAssertFalse(focus.isConfirmed)

        focus.confirm()

        XCTAssertTrue(focus.isConfirmed)
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["a"])
    }

    func testFocusLimitStaysBetweenOneAndFive() {
        XCTAssertEqual(DailyFocus(day: day, focusLimit: 0).focusLimit, 1)
        XCTAssertEqual(DailyFocus(day: day, focusLimit: 9).focusLimit, 5)
        XCTAssertEqual(DailyFocus.focusLimitRange, 1...5)
    }

    func testUnavailableTasksDegradeVisiblyWithoutDisturbingOrder() throws {
        let context = try makeInMemoryContext()
        let notionTask = TaskItem(externalTaskID: "n1", title: "Draft the brief")
        notionTask.providerWorkspaceId = "notion-workspace"
        let serverTask = TaskItem(externalTaskID: "1", title: "Call the bank")
        serverTask.providerWorkspaceId = "server-workspace"
        let removedTask = TaskItem(externalTaskID: "n2", title: "Removed")
        removedTask.providerWorkspaceId = "notion-workspace"
        removedTask.isDeleted = true
        context.insert(notionTask)
        context.insert(serverTask)
        context.insert(removedTask)

        let focus = DailyFocus(day: day, focusLimit: 5)
        try focus.add(pick("1", workspace: "server-workspace"))
        try focus.add(pick("n2"))
        try focus.add(pick("n1"))
        try focus.add(pick("n9"))

        let resolved = try focus.resolvedPicks(in: context)
        XCTAssertEqual(resolved.count, 4)
        XCTAssertEqual(resolved[0].task?.title, "Call the bank")
        XCTAssertNil(resolved[1].task)
        XCTAssertEqual(resolved[1].pick, pick("n2"))
        XCTAssertEqual(resolved[2].task?.title, "Draft the brief")
        XCTAssertNil(resolved[3].task)
        XCTAssertEqual(resolved[3].pick, pick("n9"))
    }

    func testPickingATaskLeavesPlannedDayAndDeadlineUntouched() throws {
        let task = TaskItem(externalTaskID: "n1", title: "Draft the brief")
        task.providerWorkspaceId = "notion-workspace"
        let plannedDay = day
        let deadline = day.addingTimeInterval(86_400 * 3)
        task.plannedDay = plannedDay
        task.deadline = deadline

        let focus = DailyFocus(day: day)
        try focus.add(task.dailyFocusPick)
        focus.move(fromOffsets: IndexSet(integer: 0), toOffset: 0)
        focus.confirm()
        focus.remove(task.dailyFocusPick)

        XCTAssertEqual(task.plannedDay, plannedDay)
        XCTAssertEqual(task.deadline, deadline)
        XCTAssertFalse(task.isDirty)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func pick(_ taskID: String, workspace: String = "notion-workspace") -> DailyFocusPick {
        DailyFocusPick(providerWorkspaceID: workspace, externalTaskID: taskID)
    }
}
