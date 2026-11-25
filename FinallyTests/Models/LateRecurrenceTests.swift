import XCTest
@testable import Finally

/// A recurring obligation finished long after its deadline moves to the next future date in its
/// pattern, at the same time of day.
final class LateRecurrenceTests: XCTestCase {
    private let calendar = Calendar.current

    private func lateDeadline(days: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day)!
    }

    func testWeekdayRuleReachesTheFutureAfterTwoMonths() throws {
        var rule = RecurrenceRule()
        rule.weekdays = [3]
        let next = try XCTUnwrap(rule.nextDeadline(from: lateDeadline(days: 60)))
        XCTAssertGreaterThan(next, Date())
        XCTAssertEqual(calendar.component(.weekday, from: next), 3)
        XCTAssertEqual(calendar.component(.hour, from: next), 17)
    }

    func testNthWeekdayRuleKeepsTheDeadlinesTimeAfterTwoYears() throws {
        var rule = RecurrenceRule()
        rule.frequency = .monthly
        rule.monthlyMode = .nthWeekday
        rule.nthWeekdayOrdinal = 2
        rule.nthWeekdayDay = 3
        let next = try XCTUnwrap(rule.nextDeadline(from: lateDeadline(days: 730)))
        XCTAssertGreaterThan(next, Date())
        XCTAssertEqual(calendar.component(.hour, from: next), 17)
        XCTAssertEqual(calendar.component(.minute, from: next), 30)
    }
}
