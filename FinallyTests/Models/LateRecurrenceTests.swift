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

    /// Dates far enough ahead that the rule never has to skip past today.
    private func future(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testEveryOtherWeekStaysOnItsOwnWeeks() throws {
        var rule = RecurrenceRule()
        rule.interval = 2
        rule.weekdays = [2, 4]
        let monday = future(2099, 6, 1)
        XCTAssertEqual(calendar.component(.weekday, from: monday), 2)
        let wednesday = try XCTUnwrap(rule.nextDeadline(from: monday))
        XCTAssertEqual(wednesday, future(2099, 6, 3))
        XCTAssertEqual(rule.nextDeadline(from: wednesday), future(2099, 6, 15))
    }

    func testFifthWeekdaySkipsMonthsWithoutOne() throws {
        var rule = RecurrenceRule()
        rule.frequency = .monthly
        rule.monthlyMode = .nthWeekday
        rule.nthWeekdayOrdinal = 5
        rule.nthWeekdayDay = 2
        // June 29 is the fifth Monday, and July has four.
        let next = try XCTUnwrap(rule.nextDeadline(from: future(2099, 6, 29)))
        XCTAssertEqual(next, future(2099, 8, 31))
    }

    func testLastWeekdayIsTheMonthsLast() {
        var rule = RecurrenceRule()
        rule.frequency = .monthly
        rule.monthlyMode = .nthWeekday
        rule.nthWeekdayOrdinal = -1
        rule.nthWeekdayDay = 2
        XCTAssertEqual(rule.nextDeadline(from: future(2099, 6, 29)), future(2099, 7, 27))
    }

    func testMovingTheDeadlineKeepsItsClockTimeAcrossDaylightSaving() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for (from, to) in [((3, 13), (3, 14)), ((11, 6), (11, 7))] {
            let task = TaskItem(externalTaskID: "dst", title: "Submit")
            task.deadline = newYork.date(from: DateComponents(year: 2027, month: from.0, day: from.1, hour: 17, minute: 30))
            task.deadlineHasTime = true
            let day = newYork.date(from: DateComponents(year: 2027, month: to.0, day: to.1))
            let moved = newYork.date(from: DateComponents(year: 2027, month: to.0, day: to.1, hour: 17, minute: 30))!
            XCTAssertEqual(task.scheduledDayFit(for: day, calendar: newYork), .needsDeadlineMoved(to: moved))
        }
    }
}
