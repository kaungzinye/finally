import XCTest
@testable import Finally

final class DefaultDeadlineRemindersTests: XCTestCase {
    private var settings: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DefaultDeadlineRemindersTests-\(UUID().uuidString)"
        settings = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        settings.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let deadline = Date(timeIntervalSince1970: 1_792_800_000)

    func testDefaultsStartAsMorningOfOneDayOneWeekAndOneHourBefore() {
        XCTAssertEqual(DefaultDeadlineReminders.current(in: settings).offsets,
                       [.morningOf, .daysBefore(1), .weeksBefore(1), .hourBefore])
    }

    func testEditedDefaultsPersistAndSeedTheNextNewDeadline() {
        var edited = DefaultDeadlineReminders.current(in: settings)
        edited.remove(.weeksBefore(1))
        edited.add(.daysBefore(2))
        edited.add(.daysBefore(2))
        edited.save(in: settings)
        let task = TaskItem(externalTaskID: "new", title: "Pay rent")

        task.setDeadline(deadline, hasTime: true, defaults: .current(in: settings))

        XCTAssertEqual(task.deadlineReminderOffsets, [.morningOf, .daysBefore(1), .hourBefore, .daysBefore(2)])
    }

    func testAddMenuOffersTheShortListMinusTheCurrentDefaults() {
        var edited = DefaultDeadlineReminders.standard
        edited.remove(.weeksBefore(1))

        XCTAssertEqual(edited.addableOffsets, [.daysBefore(2), .daysBefore(3), .weeksBefore(1), .weeksBefore(2)])
    }

    func testRemovingEveryDefaultLeavesNewDeadlinesWithoutReminders() {
        var edited = DefaultDeadlineReminders.current(in: settings)
        edited.offsets.forEach { edited.remove($0) }
        edited.save(in: settings)
        let task = TaskItem(externalTaskID: "quiet", title: "Water the plants")

        task.setDeadline(deadline, hasTime: true, defaults: .current(in: settings))

        XCTAssertTrue(task.taskReminders.isEmpty)
    }
}
