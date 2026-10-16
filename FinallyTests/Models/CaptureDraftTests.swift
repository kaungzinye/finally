import XCTest
@testable import Finally

final class CaptureDraftTests: XCTestCase {
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

    private func type(_ text: String, into draft: inout CaptureDraft, projects: [ProjectItem] = []) {
        draft.text = text
        draft.readText(projects: projects, now: now, calendar: calendar)
    }

    private func capture(_ text: String, projects: [ProjectItem] = []) -> TaskItem? {
        var draft = CaptureDraft()
        type(text, into: &draft, projects: projects)
        return draft.makeTask(workspaceId: "ws", defaults: .standard)
    }

    func testDueMondayCreatesADeadlineWithDefaultRemindersAndNoScheduledDay() throws {
        let task = try XCTUnwrap(capture("Tax return due mon"))

        XCTAssertEqual(task.title, "Tax return")
        XCTAssertEqual(task.deadline, day(2026, 10, 19))
        XCTAssertFalse(task.deadlineHasTime)
        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1)])
        XCTAssertNil(task.scheduledDay)
    }

    func testBareFridayCreatesAScheduledDayWithNoDeadline() throws {
        let task = try XCTUnwrap(capture("Call bank fri"))

        XCTAssertEqual(task.title, "Call bank")
        XCTAssertEqual(task.scheduledDay, day(2026, 10, 16))
        XCTAssertNil(task.deadline)
        XCTAssertTrue(task.taskReminders.isEmpty)
    }

    func testCaptureWithNoProjectLandsInTheInbox() throws {
        let task = try XCTUnwrap(capture("Call bank fri"))

        XCTAssertNil(task.project)
        XCTAssertEqual(task.providerWorkspaceId, "ws")
    }

    func testNamedProjectTakesTheTaskOutOfTheInbox() throws {
        let taxes = ProjectItem(externalProjectID: "p-taxes", title: "Taxes")

        let task = try XCTUnwrap(capture("Tax return due mon @Taxes", projects: [taxes]))

        XCTAssertEqual(task.title, "Tax return")
        XCTAssertTrue(task.project === taxes)
    }

    func testTypingDueBeforeAScheduledDayMovesItToTheDeadline() {
        var draft = CaptureDraft()

        type("Pay rent fri", into: &draft)
        XCTAssertEqual(draft.scheduledDay, day(2026, 10, 16))
        type("Pay rent due fri", into: &draft)

        XCTAssertNil(draft.scheduledDay)
        XCTAssertEqual(draft.deadline, day(2026, 10, 16))
    }

    func testEditingTheDatePhraseUpdatesTheDate() {
        var draft = CaptureDraft()

        type("Party oct 2", into: &draft)
        type("Party oct 20", into: &draft)

        XCTAssertEqual(draft.scheduledDay, day(2026, 10, 20))
    }

    func testAPickedDeadlineOutranksTheText() {
        var draft = CaptureDraft()
        draft.deadline = day(2026, 11, 1)

        type("Pay rent due fri", into: &draft)
        type("Pay rent", into: &draft)

        XCTAssertEqual(draft.deadline, day(2026, 11, 1))
    }

    func testPickingASuggestedProjectKeepsItOnceTheQueryLeavesTheText() {
        let taxes = ProjectItem(externalProjectID: "p-taxes", title: "Taxes")
        var draft = CaptureDraft()

        type("Tax return @Tax", into: &draft, projects: [taxes])
        draft.pick(project: taxes)
        type("Tax return", into: &draft, projects: [taxes])

        XCTAssertTrue(draft.project === taxes)
    }

    func testBlankTextMakesNoTask() {
        XCTAssertNil(capture("   "))
    }
}
