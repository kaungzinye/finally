import SwiftData
import XCTest
@testable import Finally

final class UpcomingDaysTests: XCTestCase {
    private var context: ModelContext!
    private var workspace: UserSession!
    private let calendar = Calendar.current
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!

    override func setUpWithError() throws {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Notion", providerIdentity: .notion)
        context.insert(workspace)
    }

    func testAScheduledTaskAppearsOnItsScheduledDay() {
        makeTask("bank", "Call bank").scheduledDay = day(2)

        let upcoming = UpcomingDays(tasks: allTasks(), workspace: workspace, at: now, calendar: calendar)

        XCTAssertEqual(upcoming.days.map(\.day), [day(2)])
        XCTAssertEqual(upcoming.days.map { $0.tasks.map(\.externalTaskID) }, [["bank"]])
    }

    func testATaskWithBothDatesAppearsOnceOnTheEarlierDay() {
        let both = makeTask("essay", "Write essay")
        both.scheduledDay = day(1)
        both.deadline = day(4)
        makeTask("rent", "Pay rent").deadline = day(4)

        let upcoming = UpcomingDays(tasks: allTasks(), workspace: workspace, at: now, calendar: calendar)

        XCTAssertEqual(upcoming.days.map(\.day), [day(1), day(4)])
        XCTAssertEqual(upcoming.days.map { $0.tasks.map(\.externalTaskID) }, [["essay"], ["rent"]])
    }

    func testAMissedScheduledDayLeavesTheTaskOnItsDeadline() {
        let task = makeTask("essay", "Write essay")
        task.scheduledDay = day(-2)
        task.deadline = day(3)

        let upcoming = UpcomingDays(tasks: allTasks(), workspace: workspace, at: now, calendar: calendar)

        XCTAssertEqual(upcoming.days.map(\.day), [day(3)])
    }

    func testUpcomingLeavesOutTodayUndatedFinishedSubtaskAndOtherWorkspaceTasks() {
        makeTask("today", "Today's task").scheduledDay = day(0)
        makeTask("undated", "Someday")
        let done = makeTask("done", "Done")
        done.deadline = day(2)
        done.status = .done
        let subtask = makeTask("step", "Step")
        subtask.scheduledDay = day(2)
        subtask.parentId = "done"
        makeTask("elsewhere", "Server task", workspace: "server-workspace").scheduledDay = day(2)

        let upcoming = UpcomingDays(tasks: allTasks(), workspace: workspace, at: now, calendar: calendar)

        XCTAssertTrue(upcoming.days.isEmpty)
    }

    func testATimedDeadlineLaterTodayAppearsToday() {
        makeTask("call", "Call back").deadline = calendar.date(byAdding: .hour, value: 6, to: now)

        let upcoming = UpcomingDays(tasks: allTasks(), workspace: workspace, at: now, calendar: calendar)

        XCTAssertEqual(upcoming.days.map(\.day), [day(0)])
    }

    // MARK: - Helpers

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @discardableResult
    private func makeTask(_ id: String, _ title: String, workspace: String = "notion-workspace") -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = workspace
        context.insert(task)
        return task
    }

    private func allTasks() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
    }
}
