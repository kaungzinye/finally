import XCTest
@testable import Finally

final class FinallyServerTaskSnapshotTests: XCTestCase {
    private let firstDay = Date(timeIntervalSince1970: 1_780_000_000)
    private let secondDay = Date(timeIntervalSince1970: 1_780_086_400)

    func testDifferences_DeadlineMovedToAnotherDateOnlyDaySendsItsTimeSetting() {
        let accepted = FinallyServerTaskMutation(title: "Proposal", deadline: firstDay, deadlineHasTime: false)
        let phone = FinallyServerTaskMutation(title: "Proposal", deadline: secondDay, deadlineHasTime: false)

        XCTAssertEqual(phone.differences(from: accepted), ["due_date", "deadline_has_time"])
    }

    func testDifferences_UnchangedDeadlineSendsNoDeadlineFields() {
        let accepted = FinallyServerTaskMutation(title: "Proposal", deadline: firstDay, deadlineHasTime: false)
        let phone = FinallyServerTaskMutation(title: "Proposal draft", deadline: firstDay, deadlineHasTime: false)

        XCTAssertEqual(phone.differences(from: accepted), ["title"])
    }
}
