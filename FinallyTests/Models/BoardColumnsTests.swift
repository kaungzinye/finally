import SwiftData
import XCTest
@testable import Finally

final class BoardColumnsTests: XCTestCase {
    private var context: ModelContext!
    private var workspace: UserSession!

    override func setUpWithError() throws {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Notion", providerIdentity: .notion)
        context.insert(workspace)
    }

    func testColumnsGroupTopLevelTasksOfTheWorkspaceByStatus() {
        makeTask("idle", "Buy stamps")
        makeTask("active", "Paint the fence").status = .inProgress
        makeTask("finished", "Return the parcel").status = .done
        makeTask("deleted", "Old idea").isDeleted = true
        makeTask("elsewhere", "Server task", workspace: "server-workspace")
        makeTask("subtask", "Find envelopes").parentId = "idle"

        let board = BoardColumns(tasks: allTasks(), workspace: workspace)

        XCTAssertEqual(board.columns.map(\.status), [.notStarted, .inProgress, .done])
        XCTAssertEqual(board.columns.map(\.title), ["Not started", "In progress", "Complete"])
        XCTAssertEqual(board.columns.map { $0.tasks.map(\.externalTaskID) }, [["idle"], ["active"], ["finished"]])
    }

    func testEachColumnListsCardsByNearestDeadlineThenScheduledDay() {
        makeTask("undated", "Pick a playlist")
        makeTask("far-deadline", "Book the venue").deadline = day(5)
        makeTask("scheduled-only", "Draft the speech").scheduledDay = day(0)
        makeTask("near-deadline", "Send invites").deadline = day(1)

        let board = BoardColumns(tasks: allTasks(), workspace: workspace)

        XCTAssertEqual(
            board.columns[0].tasks.map(\.externalTaskID),
            ["near-deadline", "far-deadline", "scheduled-only", "undated"]
        )
    }

    func testFiltersKeepTasksInAChosenProjectWithAChosenPriority() {
        let home = ProjectItem(externalProjectID: "home", title: "Home")
        home.providerWorkspaceId = "notion-workspace"
        context.insert(home)
        let match = makeTask("urgent-home", "Fix the leak")
        match.project = home
        match.priority = .urgent
        makeTask("low-home", "Dust the shelf").project = home
        makeTask("urgent-inbox", "Call the plumber").priority = .urgent

        let board = BoardColumns(tasks: allTasks(), workspace: workspace, projects: ["home"], priorities: ["Urgent"])

        XCTAssertEqual(board.columns[0].tasks.map(\.externalTaskID), ["urgent-home"])
    }

    func testADroppedCardResolvesWithinTheBoardsWorkspace() {
        makeTask("1", "Server task", workspace: "server-workspace")
        let own = makeTask("1", "Notion task")

        let board = BoardColumns(tasks: allTasks(), workspace: workspace)

        XCTAssertTrue(board.card(withID: "1") === own)
        XCTAssertNil(board.card(withID: "missing"))
    }

    // MARK: - Helpers

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_788_000_000)))!
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
