import XCTest
@testable import Finally

final class TaskStatusMappingUnitTests: XCTestCase {
    func testTaskStatus_UsesStatusGroupMembershipForCustomOptionNames() {
        let mappings = PropertyMappings(
            taskStatusSchema: NotionTestFactory.makeStatusSchema(
                options: [
                    NotionTestFactory.makeStatusOption(id: "todo-1", name: "Queued"),
                    NotionTestFactory.makeStatusOption(id: "progress-1", name: "Reviewing"),
                    NotionTestFactory.makeStatusOption(id: "done-1", name: "Shipped")
                ],
                groups: [
                    NotionTestFactory.makeStatusGroup(id: "group-1", name: "To-do", optionIds: ["todo-1"]),
                    NotionTestFactory.makeStatusGroup(id: "group-2", name: "In progress", optionIds: ["progress-1"]),
                    NotionTestFactory.makeStatusGroup(id: "group-3", name: "Complete", optionIds: ["done-1"])
                ]
            )
        )

        XCTAssertEqual(mappings.taskStatus(for: NotionStatusValue(id: "todo-1", name: "Queued")), .notStarted)
        XCTAssertEqual(mappings.taskStatus(for: NotionStatusValue(id: "progress-1", name: "Reviewing")), .inProgress)
        XCTAssertEqual(mappings.taskStatus(for: NotionStatusValue(id: "done-1", name: "Shipped")), .done)
    }

    func testNotionStatusName_PrefersRecognizedCompleteOptionOverFirstGroupOption() {
        let mappings = PropertyMappings(
            taskStatusSchema: NotionTestFactory.makeStatusSchema(
                options: [
                    NotionTestFactory.makeStatusOption(id: "done-1", name: "Archived"),
                    NotionTestFactory.makeStatusOption(id: "done-2", name: "Completed")
                ],
                groups: [
                    NotionTestFactory.makeStatusGroup(id: "group-3", name: "Complete", optionIds: ["done-1", "done-2"])
                ]
            )
        )

        XCTAssertEqual(mappings.notionStatusName(for: .done), "Completed")
    }

    func testNotionStatusName_WithoutSchema_FallsBackToLocalStatusName() {
        let mappings = PropertyMappings()

        XCTAssertEqual(mappings.notionStatusName(for: .done), TaskStatus.done.rawValue)
        XCTAssertEqual(mappings.notionStatusName(for: .inProgress), TaskStatus.inProgress.rawValue)
    }
}
