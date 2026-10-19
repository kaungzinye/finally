import XCTest
@testable import Finally

final class WorkspaceScopeTests: XCTestCase {
    func testProjectsForATaskComeFromTheTasksOwnWorkspace() {
        let task = TaskItem(externalTaskID: "t-1", title: "Renew the passport")
        task.providerWorkspaceId = "notion-ws"
        let notionProject = ProjectItem(externalProjectID: "p-notion", title: "Travel")
        notionProject.providerWorkspaceId = "notion-ws"
        let serverProject = ProjectItem(externalProjectID: "p-server", title: "Release")
        serverProject.providerWorkspaceId = "server-ws"

        XCTAssertEqual([notionProject, serverProject].available(to: task).map(\.externalProjectID), ["p-notion"])
    }
}
