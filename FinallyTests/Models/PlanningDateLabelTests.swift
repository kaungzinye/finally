import XCTest
@testable import Finally

final class PlanningDateLabelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let britain = Locale(identifier: "en_GB")
    private let australia = Locale(identifier: "en_AU")

    /// Tuesday 20 October 2026, 09:00 UTC.
    private var now: Date { at(day: 20, hour: 9) }

    func testAScheduledDayTodayReadsTodayOverItsDate() {
        let label = PlanningDateLabel(date: at(day: 20), hasTime: false, at: now, calendar: calendar, locale: britain)

        XCTAssertEqual(label.day, "Today")
        XCTAssertEqual(label.detail, "20 Oct")
        XCTAssertEqual(label.spoken, "Today")
    }

    func testADayLaterInTheWeekReadsItsWeekdayAndSpeaksTheFullDate() {
        let label = PlanningDateLabel(date: at(day: 23), hasTime: false, at: now, calendar: calendar, locale: britain)

        XCTAssertEqual(label.day, "Fri")
        XCTAssertEqual(label.detail, "23 Oct")
        XCTAssertEqual(label.spoken, "Friday 23 October")
    }

    func testTheNextAndPreviousDaysReadTomorrowAndYesterday() {
        let tomorrow = PlanningDateLabel(date: at(day: 21), hasTime: false, at: now, calendar: calendar, locale: britain)
        let yesterday = PlanningDateLabel(date: at(day: 19), hasTime: false, at: now, calendar: calendar, locale: britain)

        XCTAssertEqual(tomorrow.day, "Tomorrow")
        XCTAssertEqual(tomorrow.detail, "21 Oct")
        XCTAssertEqual(yesterday.day, "Yesterday")
        XCTAssertEqual(yesterday.spoken, "Yesterday")
    }

    func testATimedDeadlineShowsItsTimeAfterTheDate() {
        let onTheHour = PlanningDateLabel(date: at(day: 23, hour: 17), hasTime: true, at: now, calendar: calendar, locale: australia)
        let halfPast = PlanningDateLabel(date: at(day: 23, hour: 17, minute: 30), hasTime: true, at: now, calendar: calendar, locale: australia)
        let today = PlanningDateLabel(date: at(day: 20, hour: 17), hasTime: true, at: now, calendar: calendar, locale: australia)

        XCTAssertEqual(onTheHour.day, "Fri")
        XCTAssertEqual(onTheHour.detail, "23 Oct · 5\u{202F}pm")
        XCTAssertEqual(onTheHour.spoken, "Friday 23 October at 5\u{202F}pm")
        XCTAssertEqual(halfPast.detail, "23 Oct · 5:30\u{202F}pm")
        XCTAssertEqual(today.spoken, "Today at 5\u{202F}pm")
    }

    func testADayMoreThanAWeekAwayReadsItsDateOverItsWeekday() {
        let later = PlanningDateLabel(date: at(day: 29), hasTime: false, at: now, calendar: calendar, locale: britain)
        let earlier = PlanningDateLabel(date: at(day: 12), hasTime: false, at: now, calendar: calendar, locale: britain)

        XCTAssertEqual(later.day, "29 Oct")
        XCTAssertEqual(later.detail, "Thursday")
        XCTAssertEqual(later.spoken, "Thursday 29 October")
        XCTAssertEqual(earlier.day, "12 Oct")
        XCTAssertEqual(earlier.detail, "Monday")
    }

    func testATimedDeadlineMoreThanAWeekAwayShowsItsWeekdayAndTime() {
        let label = PlanningDateLabel(date: at(day: 29, hour: 17), hasTime: true, at: now, calendar: calendar, locale: australia)

        XCTAssertEqual(label.day, "29 Oct")
        XCTAssertEqual(label.detail, "Thursday · 5\u{202F}pm")
        XCTAssertEqual(label.spoken, "Thursday 29 October at 5\u{202F}pm")
    }

    func testADayInAnotherYearAddsTheYearToItsDetailAndSpokenDate() {
        let nextYear = PlanningDateLabel(date: at(day: 29, year: 2027), hasTime: false, at: now, calendar: calendar, locale: britain)
        let newYearsDay = at(day: 30, month: 12, hour: 9)
        let acrossTheYear = PlanningDateLabel(date: at(day: 2, month: 1, year: 2027), hasTime: false, at: newYearsDay, calendar: calendar, locale: britain)

        XCTAssertEqual(nextYear.day, "29 Oct")
        XCTAssertEqual(nextYear.detail, "Friday · 2027")
        XCTAssertEqual(nextYear.spoken, "Friday, 29 October 2027")
        XCTAssertEqual(acrossTheYear.day, "Sat")
        XCTAssertEqual(acrossTheYear.detail, "2 Jan 2027")
        XCTAssertEqual(acrossTheYear.spoken, "Saturday, 2 January 2027")
    }

    func testATimedDeadlineInATwentyFourHourLocaleKeepsItsMinutes() {
        let label = PlanningDateLabel(date: at(day: 23, hour: 17), hasTime: true, at: now, calendar: calendar, locale: britain)

        XCTAssertEqual(label.detail, "23 Oct · 17:00")
    }
}

private extension PlanningDateLabelTests {
    func at(day: Int, month: Int = 10, year: Int = 2026, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
