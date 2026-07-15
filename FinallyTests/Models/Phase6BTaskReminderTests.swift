import XCTest
@testable import Finally

final class Phase6BTaskReminderTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: 0))!
    }

    // MARK: - Anchored fire dates

    func testAnchoredReminder_FiresBeforeDueDate() {
        let task = TaskItem(notionPageId: "t-1", title: "Task")
        task.dueDate = makeDate(year: 2026, month: 6, day: 15, hour: 17)
        task.dueDateHasTime = true

        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .due, value: 2, unit: .hours, direction: .before)
        )

        let fire = reminder.fireDate(for: task)
        XCTAssertEqual(fire, makeDate(year: 2026, month: 6, day: 15, hour: 15))
    }

    func testAnchoredReminder_FiresAfterDueDate() {
        let task = TaskItem(notionPageId: "t-2", title: "Task")
        task.dueDate = makeDate(year: 2026, month: 6, day: 15, hour: 17)
        task.dueDateHasTime = true

        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .due, value: 1, unit: .days, direction: .after)
        )

        let fire = reminder.fireDate(for: task)
        XCTAssertEqual(fire, makeDate(year: 2026, month: 6, day: 16, hour: 17))
    }

    func testAnchoredReminder_UsesTargetAnchorWhenPresent() {
        let task = TaskItem(notionPageId: "t-3", title: "Task")
        task.targetDate = makeDate(year: 2026, month: 6, day: 10)
        task.dueDate = makeDate(year: 2026, month: 6, day: 20)

        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .target, value: 1, unit: .weeks, direction: .before)
        )

        let fire = reminder.fireDate(for: task, defaultReminderMinutes: 540)
        let expected = calendar.date(byAdding: .weekOfYear, value: -1, to: task.adjustedAnchorDate(
            task.targetDate!,
            hasTime: false,
            defaultReminderMinutes: 540
        ))
        XCTAssertEqual(fire, expected)
    }

    func testAnchoredReminder_ReturnsNilWhenAnchorDateMissing() {
        let task = TaskItem(notionPageId: "t-4", title: "No dates")
        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .due, value: 1, unit: .days, direction: .before)
        )
        XCTAssertNil(reminder.fireDate(for: task))
    }

    func testExplicitDateReminder_IsIndependentOfTaskDates() {
        let task = TaskItem(notionPageId: "t-5", title: "Task")
        let fixed = makeDate(year: 2026, month: 7, day: 4, hour: 8)
        let reminder = TaskReminder.explicitDate(ExplicitDateReminder(dateTime: fixed))

        task.dueDate = makeDate(year: 2026, month: 8, day: 1)
        XCTAssertEqual(reminder.fireDate(for: task), fixed)
    }

    // MARK: - Codec round-trip

    func testTaskReminderCodec_RoundTripsAnchoredAndExplicitReminders() {
        let reminders: [TaskReminder] = [
            .anchored(AnchoredReminder(anchor: .target, value: 3, unit: .days, direction: .before)),
            .explicitDate(ExplicitDateReminder(dateTime: makeDate(year: 2026, month: 5, day: 1, hour: 10))),
        ]

        let json = TaskReminderCodec.encode(reminders)
        let decoded = TaskReminderCodec.decode(from: json)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].displayLabel, reminders[0].displayLabel)
        XCTAssertEqual(decoded[1].displayLabel, reminders[1].displayLabel)
    }

    // MARK: - Unit bounds

    func testAnchoredReminder_ValidatesUnitBounds() {
        let valid = AnchoredReminder(anchor: .due, value: 30, unit: .days, direction: .before)
        XCTAssertTrue(valid.isValidValue())

        let invalid = AnchoredReminder(anchor: .due, value: 31, unit: .days, direction: .before)
        XCTAssertFalse(invalid.isValidValue())
    }

}
