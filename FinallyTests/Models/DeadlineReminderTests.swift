import XCTest
@testable import Finally

final class DeadlineReminderTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let nineAM = 9 * 60

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func fire(_ offset: DeadlineReminderOffset, deadline: Date?, hasTime: Bool) -> Date? {
        TaskReminder.deadline(DeadlineReminder(offset: offset))
            .fireDate(deadline: deadline, deadlineHasTime: hasTime, reminderMinutes: nineAM, calendar: calendar)
    }

    // MARK: - Fire dates

    func testTimedDeadlineResolvesTheContractExample() {
        // A deadline at 17:00 on Friday with a 09:00 default reminder time.
        let friday = date(2026, 10, 23, 17)

        XCTAssertEqual(fire(.morningOf, deadline: friday, hasTime: true), date(2026, 10, 23, 9))
        XCTAssertEqual(fire(.daysBefore(1), deadline: friday, hasTime: true), date(2026, 10, 22, 9))
        XCTAssertEqual(fire(.hourBefore, deadline: friday, hasTime: true), date(2026, 10, 23, 16))
    }

    func testDateOnlyDeadlineFiresAtTheDefaultReminderTimeOnLocalDays() {
        // Daylight saving time ends on 1 November 2026, between the reminder and the deadline.
        let deadline = date(2026, 11, 2)

        XCTAssertEqual(fire(.morningOf, deadline: deadline, hasTime: false), date(2026, 11, 2, 9))
        XCTAssertEqual(fire(.daysBefore(3), deadline: deadline, hasTime: false), date(2026, 10, 30, 9))
        XCTAssertEqual(fire(.weeksBefore(1), deadline: deadline, hasTime: false), date(2026, 10, 26, 9))
        XCTAssertEqual(fire(.weeksBefore(2), deadline: deadline, hasTime: false), date(2026, 10, 19, 9))
    }

    func testHourBeforeStaysInertWhileTheDeadlineHasNoTime() {
        XCTAssertNil(fire(.hourBefore, deadline: date(2026, 10, 23), hasTime: false))
    }

    func testDeadlineReminderAfterATimedDeadlineStaysInert() {
        // An 08:00 deadline comes before the 09:00 default reminder time on its own day.
        let early = date(2026, 10, 23, 8)

        XCTAssertNil(fire(.morningOf, deadline: early, hasTime: true))
        XCTAssertEqual(fire(.daysBefore(1), deadline: early, hasTime: true), date(2026, 10, 22, 9))
        XCTAssertEqual(fire(.morningOf, deadline: date(2026, 10, 23), hasTime: false), date(2026, 10, 23, 9))
    }

    func testExactReminderAfterATimedDeadlineStillFires() {
        let instant = date(2026, 10, 23, 10)
        let reminder = TaskReminder.exact(ExactReminder(at: instant))

        XCTAssertEqual(reminder.fireDate(deadline: date(2026, 10, 23, 8), deadlineHasTime: true, reminderMinutes: nineAM, calendar: calendar), instant)
    }

    func testDeadlineRemindersStayInertWithoutADeadline() {
        XCTAssertNil(fire(.morningOf, deadline: nil, hasTime: false))
        XCTAssertNil(fire(.weeksBefore(1), deadline: nil, hasTime: false))
        XCTAssertNil(fire(.hourBefore, deadline: nil, hasTime: true))
    }

    func testExactReminderFiresAtItsInstantWhateverTheDeadline() {
        let instant = date(2026, 10, 20, 15)
        let reminder = TaskReminder.exact(ExactReminder(at: instant))

        XCTAssertEqual(reminder.fireDate(deadline: nil, deadlineHasTime: false, reminderMinutes: nineAM, calendar: calendar), instant)
        XCTAssertEqual(reminder.fireDate(deadline: date(2026, 12, 1, 8), deadlineHasTime: true, reminderMinutes: nineAM, calendar: calendar), instant)
    }

    // MARK: - Chips

    func testChipsReadAsPlainOffsets() {
        XCTAssertEqual(DeadlineReminderOffset.morningOf.label, "Morning of")
        XCTAssertEqual(DeadlineReminderOffset.daysBefore(1).label, "1 day before")
        XCTAssertEqual(DeadlineReminderOffset.daysBefore(3).label, "3 days before")
        XCTAssertEqual(DeadlineReminderOffset.weeksBefore(1).label, "1 week before")
        XCTAssertEqual(DeadlineReminderOffset.weeksBefore(2).label, "2 weeks before")
        XCTAssertEqual(DeadlineReminderOffset.hourBefore.label, "1 hour before")
    }

    func testAddMenuOffersTheShortListMinusTheTasksChips() {
        let task = TaskItem(externalTaskID: "menu", title: "Submit the grant")
        task.setDeadline(date(2026, 10, 23), hasTime: false, defaults: .standard)

        XCTAssertEqual(task.addableDeadlineReminderOffsets, [.daysBefore(2), .daysBefore(3), .weeksBefore(2)])

        task.setDeadline(date(2026, 10, 23, 17), hasTime: true, defaults: DefaultDeadlineReminders(offsets: [.morningOf]))

        XCTAssertEqual(task.addableDeadlineReminderOffsets, [.daysBefore(2), .daysBefore(3), .weeksBefore(2), .hourBefore])
    }

    func testAddMenuIsEmptyWithoutADeadline() {
        XCTAssertTrue(TaskItem(externalTaskID: "none", title: "Someday").addableDeadlineReminderOffsets.isEmpty)
    }

    // MARK: - Default deadline reminders

    func testANewTimedDeadlineReceivesEveryDefault() {
        let task = TaskItem(externalTaskID: "timed", title: "File taxes")

        task.setDeadline(date(2026, 10, 23, 17), hasTime: true, defaults: .standard)

        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1), .hourBefore])
    }

    func testANewDateOnlyDeadlineSkipsTheHourBeforeDefault() {
        let task = TaskItem(externalTaskID: "date-only", title: "Renew passport")

        task.setDeadline(date(2026, 10, 23), hasTime: false, defaults: .standard)

        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1)])
    }

    func testMovingTheDeadlineKeepsTheTasksOwnList() throws {
        let task = TaskItem(externalTaskID: "moved", title: "Ship the proposal")
        task.setDeadline(date(2026, 10, 23, 17), hasTime: true, defaults: .standard)
        let weekBefore = try XCTUnwrap(task.taskReminders.first { reminder in
            if case .deadline(let rule) = reminder { rule.offset == .weeksBefore(1) } else { false }
        })
        task.removeReminder(id: weekBefore.id)
        task.addDeadlineReminder(.daysBefore(3))
        let edited = task.taskReminders

        task.setDeadline(date(2026, 10, 30, 12), hasTime: true, defaults: .standard)

        XCTAssertEqual(task.taskReminders, edited)
        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .hourBefore, .daysBefore(3)])
        XCTAssertEqual(task.taskReminders.compactMap { $0.fireDate(deadline: task.deadline, deadlineHasTime: true, reminderMinutes: nineAM, calendar: calendar) },
                       [date(2026, 10, 30, 9), date(2026, 10, 29, 9), date(2026, 10, 30, 11), date(2026, 10, 27, 9)])
    }

    func testSettingAClearedDeadlineAgainStartsFromTheDefaults() {
        let task = TaskItem(externalTaskID: "cleared", title: "Book flights")
        task.setDeadline(date(2026, 10, 23), hasTime: false, defaults: .standard)
        task.addDeadlineReminder(.daysBefore(3))
        task.setDeadline(nil, hasTime: false, defaults: .standard)

        XCTAssertEqual(task.deadlineReminderOffsets, [])

        task.setDeadline(date(2026, 11, 6, 10), hasTime: true, defaults: .standard)

        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1), .hourBefore])
    }

    func testClearingTheDeadlineKeepsExactReminders() {
        let task = TaskItem(externalTaskID: "exact", title: "Call the bank")
        task.setDeadline(date(2026, 10, 23), hasTime: false, defaults: .standard)
        task.taskReminders.append(.exact(ExactReminder(at: date(2026, 10, 20, 15))))

        task.setDeadline(nil, hasTime: false, defaults: .standard)

        XCTAssertEqual(task.taskReminders.count, 1)
    }

    func testADeadlineGainingATimeAddsTheHourBeforeDefault() {
        let task = TaskItem(externalTaskID: "timed", title: "Ship the release notes")
        task.setDeadline(date(2026, 10, 23), hasTime: false, defaults: .standard)
        task.addDeadlineReminder(.daysBefore(3))

        task.setDeadline(date(2026, 10, 23, 17), hasTime: true, defaults: .standard)

        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .weeksBefore(1), .daysBefore(3), .hourBefore])
    }

    func testADeadlineGainingATimeSkipsHourBeforeWhenTheDefaultsLeaveItOut() {
        let task = TaskItem(externalTaskID: "timed-off", title: "Ship the release notes")
        let defaults = DefaultDeadlineReminders(offsets: [.morningOf])
        task.setDeadline(date(2026, 10, 23), hasTime: false, defaults: defaults)

        task.setDeadline(date(2026, 10, 23, 17), hasTime: true, defaults: defaults)

        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf])
    }

    func testARecurrenceCycleKeepsTheOffsetsAgainstTheNextDeadline() {
        let task = TaskItem(externalTaskID: "weekly", title: "Send the weekly report")
        task.recurrence = .weekly
        // Recurrence advances past today, so the cycle sits in a future June clear of any DST change.
        task.setDeadline(date(2027, 6, 11, 17), hasTime: true, defaults: .standard)
        let rules = task.taskReminders

        XCTAssertTrue(task.complete())

        XCTAssertEqual(task.taskReminders, rules)
        XCTAssertEqual(task.taskReminders.compactMap { $0.fireDate(deadline: task.deadline, deadlineHasTime: task.deadlineHasTime, reminderMinutes: nineAM, calendar: calendar) },
                       [date(2027, 6, 18, 9), date(2027, 6, 17, 9), date(2027, 6, 11, 9), date(2027, 6, 18, 16)])
    }
}
