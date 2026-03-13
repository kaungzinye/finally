import XCTest
@testable import Finally

final class SchemaValidatorUnitTests: XCTestCase {
    func testValidateTasksDatabase_WithValidSchema_ReturnsValidAndMappings() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "status"),
                "Due Date": NotionTestFactory.schema(type: "date"),
                "Priority": NotionTestFactory.schema(type: "select"),
                "Tags": NotionTestFactory.schema(type: "multi_select"),
                "Project": NotionTestFactory.schema(type: "relation"),
                "Recurrence": NotionTestFactory.schema(type: "select"),
            ])
        ]

        let validator = SchemaValidator(api: mock)
        let (result, mappings) = try await validator.validateTasksDatabase(id: "tasks-db")

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(mappings.taskStatusProperty, "Status")
        XCTAssertEqual(mappings.taskDueDateProperty, "Due Date")
        XCTAssertEqual(mappings.taskPriorityProperty, "Priority")
        XCTAssertEqual(mappings.taskTagsProperty, "Tags")
        XCTAssertEqual(mappings.taskProjectProperty, "Project")
        XCTAssertEqual(mappings.taskRecurrenceProperty, "Recurrence")
    }

    func testValidateTasksDatabase_WhenStatusTypeIsWrong_ReturnsExplicitMismatchError() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "rich_text"),
                "Due Date": NotionTestFactory.schema(type: "date"),
            ])
        ]

        let validator = SchemaValidator(api: mock)
        let (result, _) = try await validator.validateTasksDatabase(id: "tasks-db")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.propertyName == "Status" && $0.expectedType == "status" })
    }

    func testValidateTasksDatabase_WhenStatusWrongTypeEvenIfAnotherStatusExists_StillFailsForStatusField() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "select"),
                "Workflow State": NotionTestFactory.schema(type: "status"),
                "Due Date": NotionTestFactory.schema(type: "date"),
            ])
        ]

        let validator = SchemaValidator(api: mock)
        let (result, mappings) = try await validator.validateTasksDatabase(id: "tasks-db")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.propertyName == "Status" && $0.expectedType == "status" })
        XCTAssertNotEqual(mappings.taskStatusProperty, "Workflow State")
    }

    func testValidateTasksDatabase_WhenStatusRenamedToState_FailsBecauseStatusFieldIsRequired() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "State": NotionTestFactory.schema(type: "status"),
                "Due Date": NotionTestFactory.schema(type: "date"),
            ])
        ]

        let validator = SchemaValidator(api: mock)
        let (result, _) = try await validator.validateTasksDatabase(id: "tasks-db")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.propertyName == "Status" && $0.expectedType == "status" })
    }

    func testValidateTasksDatabase_WhenDueDateTypeIsWrong_ReturnsExplicitMismatchError() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "status"),
                "Due Date": NotionTestFactory.schema(type: "rich_text"),
                "Start": NotionTestFactory.schema(type: "date"),
            ])
        ]

        let validator = SchemaValidator(api: mock)
        let (result, _) = try await validator.validateTasksDatabase(id: "tasks-db")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.propertyName == "Due Date" && $0.expectedType == "date" })
    }

    func testValidateTasksDatabase_WhenMultipleDateFieldsAndNoDueName_ReturnsAmbiguousCandidates() async throws {
        let mock = MockNotionAPIClient()
        mock.retrieveDatabaseQueue = [
            NotionTestFactory.makeDatabase(properties: [
                "Name": NotionTestFactory.schema(type: "title"),
                "Status": NotionTestFactory.schema(type: "status"),
                "Start": NotionTestFactory.schema(type: "date"),
                "End": NotionTestFactory.schema(type: "date"),
            ])
        ]

        let validator = SchemaValidator(api: mock)
        let (result, mappings) = try await validator.validateTasksDatabase(id: "tasks-db")

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(Set(result.ambiguousDueDateCandidates), Set(["Start", "End"]))
        XCTAssertEqual(mappings.taskDueDateProperty, "Start")
    }
}
