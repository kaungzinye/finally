import XCTest
@testable import Finally

final class RecurrenceTests: XCTestCase {
    func testDailyRecurrence() {
        let recurrence = Recurrence.daily
        let baseDate = Calendar.current.startOfDay(for: Date())
        let next = recurrence.nextDueDate(from: baseDate)
        XCTAssertNotNil(next)
    }

    func testNoneRecurrence() {
        let recurrence = Recurrence.none
        let next = recurrence.nextDueDate(from: Date())
        XCTAssertNil(next)
    }
}
