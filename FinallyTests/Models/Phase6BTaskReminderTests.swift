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

    func testReminderAnchorsUseCanonicalNamesAndResolveDates() {
        let task = TaskItem(externalTaskID: "canonical-anchors", title: "Plan launch")
        let plannedDay = makeDate(year: 2026, month: 9, day: 14)
        let deadline = makeDate(year: 2026, month: 9, day: 21, hour: 17)
        task.plannedDay = plannedDay
        task.deadline = deadline

        XCTAssertEqual(ReminderAnchor.plannedDay.rawValue, "plannedDay")
        XCTAssertEqual(ReminderAnchor.deadline.rawValue, "deadline")
        XCTAssertEqual(task.anchorDate(for: .plannedDay), plannedDay)
        XCTAssertEqual(task.anchorDate(for: .deadline), deadline)
    }

    func testAnchoredReminder_FiresBeforeDeadline() {
        let task = TaskItem(externalTaskID: "t-1", title: "Task")
        task.deadline = makeDate(year: 2026, month: 6, day: 15, hour: 17)
        task.deadlineHasTime = true

        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .deadline, value: 2, unit: .hours, direction: .before)
        )

        let fire = reminder.fireDate(for: task)
        XCTAssertEqual(fire, makeDate(year: 2026, month: 6, day: 15, hour: 15))
    }

    func testAnchoredReminder_FiresAfterDeadline() {
        let task = TaskItem(externalTaskID: "t-2", title: "Task")
        task.deadline = makeDate(year: 2026, month: 6, day: 15, hour: 17)
        task.deadlineHasTime = true

        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .deadline, value: 1, unit: .days, direction: .after)
        )

        let fire = reminder.fireDate(for: task)
        XCTAssertEqual(fire, makeDate(year: 2026, month: 6, day: 16, hour: 17))
    }

    func testAnchoredReminder_UsesPlannedDayAnchorWhenPresent() {
        let task = TaskItem(externalTaskID: "t-3", title: "Task")
        task.plannedDay = makeDate(year: 2026, month: 6, day: 10)
        task.deadline = makeDate(year: 2026, month: 6, day: 20)

        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .plannedDay, value: 1, unit: .weeks, direction: .before)
        )

        let fire = reminder.fireDate(for: task, defaultReminderMinutes: 540)
        let expected = calendar.date(byAdding: .weekOfYear, value: -1, to: task.adjustedAnchorDate(
            task.plannedDay!,
            hasTime: false,
            defaultReminderMinutes: 540
        ))
        XCTAssertEqual(fire, expected)
    }

    func testAnchoredReminder_ReturnsNilWhenAnchorDateMissing() {
        let task = TaskItem(externalTaskID: "t-4", title: "No dates")
        let reminder = TaskReminder.anchored(
            AnchoredReminder(anchor: .deadline, value: 1, unit: .days, direction: .before)
        )
        XCTAssertNil(reminder.fireDate(for: task))
    }

    func testExplicitDateReminder_IsIndependentOfTaskDates() {
        let task = TaskItem(externalTaskID: "t-5", title: "Task")
        let fixed = makeDate(year: 2026, month: 7, day: 4, hour: 8)
        let reminder = TaskReminder.explicitDate(ExplicitDateReminder(dateTime: fixed))

        task.deadline = makeDate(year: 2026, month: 8, day: 1)
        XCTAssertEqual(reminder.fireDate(for: task), fixed)
    }

    // MARK: - Codec round-trip

    func testTaskReminderCodec_RoundTripsAnchoredAndExplicitReminders() {
        let reminders: [TaskReminder] = [
            .anchored(AnchoredReminder(anchor: .plannedDay, value: 3, unit: .days, direction: .before)),
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
        let valid = AnchoredReminder(anchor: .deadline, value: 30, unit: .days, direction: .before)
        XCTAssertTrue(valid.isValidValue())

        let invalid = AnchoredReminder(anchor: .deadline, value: 31, unit: .days, direction: .before)
        XCTAssertFalse(invalid.isValidValue())
    }

}
