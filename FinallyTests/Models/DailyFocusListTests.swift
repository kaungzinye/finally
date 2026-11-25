import XCTest
@testable import Finally

final class DailyFocusListTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_788_000_000))

    func testRowsNumberPicksInOrderAndMarkTheFirstOpenPickAsWhereToStart() throws {
        let brief = task("brief", "Draft the brief", status: .done)
        let release = task("release", "Ship the release")
        let bank = task("bank", "Call the bank")
        let focus = DailyFocus(day: day, focusLimit: 4)
        focus.picks = [brief.dailyFocusPick, release.dailyFocusPick, bank.dailyFocusPick]

        let list = DailyFocusList(focus: focus, tasks: [brief, release, bank])

        XCTAssertEqual(list.rows.map(\.number), [1, 2, 3])
        XCTAssertEqual(list.rows.map { $0.task?.title }, ["Draft the brief", "Ship the release", "Call the bank"])
        XCTAssertEqual(list.rows.map(\.isNext), [false, true, false])
        XCTAssertEqual(list.emptySlotNumbers, [4])
    }

    func testADonePickCollapsesInItsPlaceAndCountsTowardTheStatus() throws {
        let brief = task("brief", "Draft the brief")
        let release = task("release", "Ship the release", status: .done)
        let focus = DailyFocus(day: day)
        focus.picks = [brief.dailyFocusPick, release.dailyFocusPick, pick("gone")]

        let list = DailyFocusList(focus: focus, tasks: [brief, release])

        XCTAssertEqual(list.rows.map(\.isDone), [false, true, false])
        XCTAssertEqual(list.status, "1 of 3 done")
    }

    func testANewDayAsksForPicksFromToday() {
        let list = DailyFocusList(focus: DailyFocus(day: day, focusLimit: 5), tasks: [])

        XCTAssertTrue(list.rows.isEmpty)
        XCTAssertEqual(list.emptySlotNumbers, [1, 2, 3, 4, 5])
        XCTAssertEqual(list.status, "Pick from Today")
    }

    func testDraggingARowReordersEveryPickDoneOnesIncluded() throws {
        let brief = task("brief", "Draft the brief", status: .done)
        let release = task("release", "Ship the release")
        let bank = task("bank", "Call the bank")
        let focus = DailyFocus(day: day)
        focus.picks = [brief.dailyFocusPick, release.dailyFocusPick, bank.dailyFocusPick]
        let tasks = [brief, release, bank]

        DailyFocusList(focus: focus, tasks: tasks).move(in: focus, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["bank", "brief", "release"])

        DailyFocusList(focus: focus, tasks: tasks).move(in: focus, fromOffsets: IndexSet(integer: 1), toOffset: 3)
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["bank", "release", "brief"])

        let list = DailyFocusList(focus: focus, tasks: tasks)
        XCTAssertEqual(list.rows.map { $0.task?.title }, ["Call the bank", "Ship the release", "Draft the brief"])
        XCTAssertEqual(list.rows.map(\.number), [1, 2, 3])
        XCTAssertEqual(list.rows.map(\.isNext), [true, false, false])
    }

    func testAnOpenPickedParentShowsItsNextStepOnce() throws {
        let parent = task("parent", "Prepare the brief")
        let step = task("step", "Write the outline")
        parent.subtasks = [step]
        let bank = task("bank", "Call the bank")
        let focus = DailyFocus(day: day)
        focus.picks = [parent.dailyFocusPick, step.dailyFocusPick, bank.dailyFocusPick]
        let tasks = [parent, step, bank]

        let list = DailyFocusList(focus: focus, tasks: tasks)
        XCTAssertEqual(list.rows.map { $0.task?.title }, ["Write the outline", "Call the bank"])
        XCTAssertEqual(list.rows.map(\.number), [1, 2])
        XCTAssertEqual(list.emptySlotNumbers, [])

        list.move(in: focus, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(focus.picks.map(\.externalTaskID), ["bank", "step", "parent"])
    }

    private func pick(_ id: String) -> DailyFocusPick {
        DailyFocusPick(providerWorkspaceID: "notion-workspace", externalTaskID: id)
    }

    private func task(_ id: String, _ title: String, status: TaskStatus = .notStarted) -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = "notion-workspace"
        task.status = status
        return task
    }
}
