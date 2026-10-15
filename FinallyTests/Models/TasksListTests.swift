import SwiftData
import XCTest
@testable import Finally

final class TasksListTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_788_000_000))
    private var context: ModelContext!
    private var workspace: UserSession!

    override func setUpWithError() throws {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        workspace = UserSession(workspaceId: "notion-workspace", workspaceName: "Notion", providerIdentity: .notion)
        context.insert(workspace)
    }

    func testInboxHoldsOpenTasksWithNoProjectInTheSelectedWorkspace() {
        let project = makeProject("home", "Home")
        let unsorted = makeTask("unsorted", "Buy stamps")
        makeTask("filed", "Paint the fence", project: project)
        makeTask("finished", "Return the parcel").status = .done
        makeTask("deleted", "Old idea").isDeleted = true
        makeTask("elsewhere", "Server task", workspace: "server-workspace")
        let subtask = makeTask("subtask", "Find envelopes")
        subtask.parentId = unsorted.externalTaskID

        let list = TasksList(tasks: allTasks(), projects: allProjects(), workspace: workspace)

        XCTAssertEqual(list.inbox.map(\.externalTaskID), ["unsorted"])
    }

    func testEachProjectShowsItsThreeNearestTasksByDeadlineThenScheduledDay() {
        let launch = makeProject("launch", "Launch")
        let garden = makeProject("garden", "Garden")
        makeTask("far-deadline", "Book the venue", project: launch).deadline = day(5)
        makeTask("near-deadline", "Send invites", project: launch).deadline = day(1)
        makeTask("scheduled-only", "Draft the speech", project: launch).scheduledDay = day(0)
        let tied = makeTask("near-deadline-scheduled", "Order banners", project: launch)
        tied.deadline = day(1)
        tied.scheduledDay = day(-2)
        makeTask("undated", "Pick a playlist", project: launch)
        let finished = makeTask("finished", "Reserve the room", project: launch)
        finished.deadline = day(-1)
        finished.status = .done

        let list = TasksList(tasks: allTasks(), projects: allProjects(), workspace: workspace)

        XCTAssertEqual(list.projects.map(\.project.title), ["Garden", "Launch"])
        let launchGroup = list.projects[1]
        XCTAssertEqual(launchGroup.nearest.map(\.externalTaskID), ["near-deadline-scheduled", "near-deadline", "far-deadline"])
        XCTAssertEqual(launchGroup.moreCount, 2)
        XCTAssertEqual(list.projects[0].project, garden)
        XCTAssertTrue(list.projects[0].nearest.isEmpty)
        XCTAssertEqual(list.projects[0].moreCount, 0)
    }

    func testUnscheduledFilterKeepsTasksWithNeitherScheduledDayNorDeadline() {
        let launch = makeProject("launch", "Launch")
        let garden = makeProject("garden", "Garden")
        makeTask("inbox-undated", "Sort receipts")
        makeTask("inbox-scheduled", "Water plants").scheduledDay = day(2)
        makeTask("launch-deadline", "Send invites", project: launch).deadline = day(1)
        makeTask("launch-undated", "Pick a playlist", project: launch)
        makeTask("garden-scheduled", "Plant bulbs", project: garden).scheduledDay = day(3)

        let list = TasksList(tasks: allTasks(), projects: allProjects(), workspace: workspace, unscheduledOnly: true)

        XCTAssertEqual(list.inbox.map(\.externalTaskID), ["inbox-undated"])
        XCTAssertEqual(list.projects.map(\.project.title), ["Launch"])
        XCTAssertEqual(list.projects[0].nearest.map(\.externalTaskID), ["launch-undated"])
        XCTAssertEqual(list.projects[0].moreCount, 0)
    }

    // MARK: - Fixtures

    @discardableResult
    private func makeTask(
        _ id: String,
        _ title: String,
        project: ProjectItem? = nil,
        workspace: String = "notion-workspace"
    ) -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = workspace
        context.insert(task)
        task.project = project
        return task
    }

    private func makeProject(_ id: String, _ title: String) -> ProjectItem {
        let project = ProjectItem(externalProjectID: id, title: title)
        project.providerWorkspaceId = "notion-workspace"
        context.insert(project)
        return project
    }

    private func allTasks() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
    }

    private func allProjects() -> [ProjectItem] {
        (try? context.fetch(FetchDescriptor<ProjectItem>())) ?? []
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }
}
