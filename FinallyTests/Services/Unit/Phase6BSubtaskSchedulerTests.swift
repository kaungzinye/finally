import XCTest
@testable import Finally

final class Phase6BSubtaskSchedulerTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    func testDistributeSubtaskDates_PrefersTargetDateOverDueDate() {
        let parent = TaskItem(notionPageId: "parent", title: "Parent")
        parent.targetDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        parent.dueDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        let sub1 = TaskItem(notionPageId: "sub-1", title: "First")
        sub1.parentId = parent.notionPageId
        sub1.sortIndex = 0

        let sub2 = TaskItem(notionPageId: "sub-2", title: "Second")
        sub2.parentId = parent.notionPageId
        sub2.sortIndex = 1

        parent.subtasks = [sub1, sub2]

        SubtaskScheduler.distributeSubtaskDates(parent: parent)

        XCTAssertNotNil(sub1.suggestedDate)
        XCTAssertNotNil(sub2.suggestedDate)
        if let d1 = sub1.suggestedDate, let d2 = sub2.suggestedDate {
            XCTAssertLessThanOrEqual(d1, d2)
            XCTAssertLessThanOrEqual(d2, parent.targetDate!)
        }
    }

    func testDistributeSubtaskDates_RespectsSuggestedDateOverride() {
        let parent = TaskItem(notionPageId: "parent", title: "Parent")
        parent.dueDate = calendar.date(byAdding: .day, value: 14, to: Date())!

        let sub = TaskItem(notionPageId: "sub-1", title: "Locked")
        sub.parentId = parent.notionPageId
        sub.sortIndex = 0
        let override = calendar.date(byAdding: .day, value: 3, to: Date())!
        sub.suggestedDateOverride = override
        parent.subtasks = [sub]

        SubtaskScheduler.distributeSubtaskDates(parent: parent)

        XCTAssertEqual(sub.effectiveSuggestedDate, override)
    }
}
