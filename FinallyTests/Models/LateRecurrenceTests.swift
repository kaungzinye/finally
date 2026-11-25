import XCTest
@testable import Finally

/// A recurring obligation moves to the next date in its pattern after now, however late it is
/// finished, at the same time of day.
final class LateRecurrenceTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func nthWeekday(_ ordinal: Int, _ weekday: Int) -> RecurrenceRule {
        var rule = RecurrenceRule()
        rule.frequency = .monthly
        rule.monthlyMode = .nthWeekday
        rule.nthWeekdayOrdinal = ordinal
        rule.nthWeekdayDay = weekday
        return rule
    }

    func testWeekdayRuleReachesTheNextTuesdayAfterTwoMonths() {
        var rule = RecurrenceRule()
        rule.weekdays = [3]
        XCTAssertEqual(rule.nextDeadline(from: date(2026, 6, 2, 17, 30), after: date(2026, 8, 5), calendar: calendar()),
                       date(2026, 8, 11, 17, 30))
    }

    func testNthWeekdayRuleReachesTheNextSecondTuesdayAfterTwoYears() {
        XCTAssertEqual(nthWeekday(2, 3).nextDeadline(from: date(2024, 6, 11, 17, 30), after: date(2026, 6, 10), calendar: calendar()),
                       date(2026, 7, 14, 17, 30))
    }

    func testEveryOtherWeekStaysOnItsOwnWeeks() {
        var rule = RecurrenceRule()
        rule.interval = 2
        rule.weekdays = [2, 4]
        for firstWeekday in [1, 2] {
            let calendar = calendar(firstWeekday: firstWeekday)
            XCTAssertEqual(rule.nextDeadline(from: date(2026, 6, 1), after: date(2026, 6, 1), calendar: calendar), date(2026, 6, 3))
            XCTAssertEqual(rule.nextDeadline(from: date(2026, 6, 3), after: date(2026, 6, 3), calendar: calendar), date(2026, 6, 15))
        }
    }

    func testFifthWeekdaySkipsMonthsWithoutOne() {
        XCTAssertEqual(nthWeekday(5, 2).nextDeadline(from: date(2026, 6, 29), after: date(2026, 6, 29), calendar: calendar()),
                       date(2026, 8, 31))
    }

    func testLastWeekdayIsTheMonthsLast() {
        XCTAssertEqual(nthWeekday(-1, 2).nextDeadline(from: date(2026, 6, 29), after: date(2026, 6, 29), calendar: calendar()),
                       date(2026, 7, 27))
    }

    func testLateFinishPastASpringClockChangeKeepsTheTimeOfDay() {
        var rule = RecurrenceRule()
        rule.frequency = .daily
        let deadline = date(2027, 3, 13, 2)
        XCTAssertEqual(rule.nextDeadline(from: deadline, after: date(2027, 3, 14, 12), calendar: calendar()), date(2027, 3, 15, 2))
        XCTAssertEqual(Recurrence.daily.nextDeadline(from: deadline, after: date(2027, 3, 14, 12), calendar: calendar()), date(2027, 3, 15, 2))
        rule.frequency = .weekly
        rule.weekdays = Set(1...7)
        XCTAssertEqual(rule.nextDeadline(from: deadline, after: date(2027, 3, 14, 12), calendar: calendar()), date(2027, 3, 15, 2))
    }

    func testEveryWeekdaySkipsTheWeekendAndKeepsTheTimeOfDay() {
        // Friday March 12, finished during the clock change weekend.
        XCTAssertEqual(Recurrence.everyWeekday.nextDeadline(from: date(2027, 3, 12, 2, 30), after: date(2027, 3, 14, 12), calendar: calendar()),
                       date(2027, 3, 15, 2, 30))
    }

    func testLateFinishPastAShortMonthKeepsTheDay() {
        XCTAssertEqual(Recurrence.monthly.nextDeadline(from: date(2027, 1, 31), after: date(2027, 3, 1), calendar: calendar()),
                       date(2027, 3, 31))
    }

    func testMovingTheDeadlineKeepsItsClockTimeAcrossDaylightSaving() {
        for (from, to) in [((3, 13), (3, 14)), ((11, 6), (11, 7))] {
            let task = TaskItem(externalTaskID: "dst", title: "Submit")
            task.deadline = date(2027, from.0, from.1, 17, 30)
            task.deadlineHasTime = true
            XCTAssertEqual(task.scheduledDayFit(for: date(2027, to.0, to.1, 0), calendar: calendar()),
                           .needsDeadlineMoved(to: date(2027, to.0, to.1, 17, 30)))
        }
    }
}
