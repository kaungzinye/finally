import XCTest
@testable import Finally

final class TaskTitleParserTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 12 October 2026, mid-morning.
    private var now: Date { day(2026, 10, 12).addingTimeInterval(10 * 3600) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func parse(_ text: String) -> TaskTitleParseResult {
        TaskTitleParser.parse(text, now: now, calendar: calendar)
    }

    // MARK: - Bare dates set the scheduled day

    func testBareWeekdaySetsTheScheduledDay() {
        let result = parse("Call the bank fri")

        XCTAssertEqual(result.cleanTitle, "Call the bank")
        XCTAssertEqual(result.scheduledDay, day(2026, 10, 16))
        XCTAssertNil(result.deadline)
    }

    // MARK: - "due" and "by" set the deadline

    func testDuePhraseSetsTheDeadlineAndNoScheduledDay() {
        let result = parse("Pay rent due fri")

        XCTAssertEqual(result.cleanTitle, "Pay rent")
        XCTAssertEqual(result.deadline, day(2026, 10, 16))
        XCTAssertNil(result.scheduledDay)
    }

    func testByPhraseSetsTheDeadline() {
        let result = parse("Submit the form by oct 20")

        XCTAssertEqual(result.cleanTitle, "Submit the form")
        XCTAssertEqual(result.deadline, day(2026, 10, 20))
        XCTAssertNil(result.scheduledDay)
    }

    func testTaxReturnDueMondayHasOnlyADeadline() {
        let result = parse("Tax return due mon")

        XCTAssertEqual(result.cleanTitle, "Tax return")
        XCTAssertEqual(result.deadline, day(2026, 10, 19))
        XCTAssertNil(result.scheduledDay)
    }

    func testDueAndByAreCaseInsensitive() {
        XCTAssertEqual(parse("Pay rent Due Friday").deadline, day(2026, 10, 16))
        XCTAssertEqual(parse("Pay rent BY TOMORROW").deadline, day(2026, 10, 13))
    }

    func testEveryDatePhraseWorksAfterDue() {
        XCTAssertEqual(parse("A due today").deadline, day(2026, 10, 12))
        XCTAssertEqual(parse("A due next week").deadline, day(2026, 10, 19))
        XCTAssertEqual(parse("A due next month").deadline, day(2026, 11, 1))
        XCTAssertEqual(parse("A due in 2 weeks").deadline, day(2026, 10, 26))
        XCTAssertEqual(parse("A due 10/20").deadline, day(2026, 10, 20))
    }

    // MARK: - Titles holding both dates

    func testTitleWithBothDatesSetsEach() {
        let result = parse("Draft essay tomorrow due fri")

        XCTAssertEqual(result.cleanTitle, "Draft essay")
        XCTAssertEqual(result.scheduledDay, day(2026, 10, 13))
        XCTAssertEqual(result.deadline, day(2026, 10, 16))
    }

    func testDeadlinePhraseMayComeFirst() {
        let result = parse("Pay rent by oct 20 work on it thursday")

        XCTAssertEqual(result.cleanTitle, "Pay rent work on it")
        XCTAssertEqual(result.deadline, day(2026, 10, 20))
        XCTAssertEqual(result.scheduledDay, day(2026, 10, 15))
    }

    // MARK: - Bare date phrases

    func testBareDatePhrasesSetTheScheduledDay() {
        XCTAssertEqual(parse("A today").scheduledDay, day(2026, 10, 12))
        XCTAssertEqual(parse("A tomorrow").scheduledDay, day(2026, 10, 13))
        XCTAssertEqual(parse("A thursday").scheduledDay, day(2026, 10, 15))
        XCTAssertEqual(parse("A next week").scheduledDay, day(2026, 10, 19))
        XCTAssertEqual(parse("A in 3 days").scheduledDay, day(2026, 10, 15))
        XCTAssertEqual(parse("A in 1 month").scheduledDay, day(2026, 11, 12))
        XCTAssertEqual(parse("A oct 20").scheduledDay, day(2026, 10, 20))
        XCTAssertEqual(parse("A October 20").scheduledDay, day(2026, 10, 20))
        XCTAssertEqual(parse("A 12/25").scheduledDay, day(2026, 12, 25))
    }

    func testTodaysWeekdayMeansNextWeek() {
        XCTAssertEqual(parse("Stand-up mon").scheduledDay, day(2026, 10, 19))
    }

    func testPastMonthDayRollsIntoNextYear() {
        XCTAssertEqual(parse("Renew passport jan 5").scheduledDay, day(2027, 1, 5))
    }

    // MARK: - Text that is not a date

    func testWordsHoldingDateWordsStayInTheTitle() {
        let result = parse("Fix the sunroof by the marble 5 steps")

        XCTAssertEqual(result.cleanTitle, "Fix the sunroof by the marble 5 steps")
        XCTAssertNil(result.scheduledDay)
        XCTAssertNil(result.deadline)
    }

    func testDueWithoutADateStaysInTheTitle() {
        let result = parse("Find what is due")

        XCTAssertEqual(result.cleanTitle, "Find what is due")
        XCTAssertNil(result.deadline)
    }

    func testImpossibleDayIsNotADate() {
        let result = parse("Party feb 30")

        XCTAssertEqual(result.cleanTitle, "Party feb 30")
        XCTAssertNil(result.scheduledDay)
    }

    // MARK: - Other fields beside dates

    func testDatesParseAlongsidePriorityProjectAndTags() {
        let result = parse("Tax return due mon @Taxes !!1 #irs")

        XCTAssertEqual(result.cleanTitle, "Tax return")
        XCTAssertEqual(result.deadline, day(2026, 10, 19))
        XCTAssertEqual(result.detectedProjectName, "Taxes")
        XCTAssertEqual(result.detectedPriority, .urgent)
        XCTAssertEqual(result.detectedTags, ["irs"])
    }
}
