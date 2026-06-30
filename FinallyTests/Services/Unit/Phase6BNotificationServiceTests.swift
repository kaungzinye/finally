import XCTest
import SwiftData
import UserNotifications
@testable import Finally

final class Phase6BNotificationServiceTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 2_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, ReminderItem.self, UserSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testScheduleReminder_WithAnchoredTaskReminder_SchedulesNotification() throws {
        let ctx = try makeContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-1", title: "Buy milk")
        task.dueDate = now.addingTimeInterval(3600)
        task.dueDateHasTime = true
        ctx.insert(task)

        let reminder = TaskReminder.presetThirtyMinutesBeforeDue()
        task.taskReminders = [reminder]
        try ctx.save()

        let service = NotificationService(center: scheduler, now: { now })
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        XCTAssertEqual(scheduler.addedRequests.first?.identifier, reminder.notificationId)
    }

    func testRescheduleAll_UsesTaskRemindersJSON() throws {
        let ctx = try makeContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-2", title: "Future task")
        task.dueDate = now.addingTimeInterval(2 * 86_400)
        task.dueDateHasTime = true
        task.taskReminders = [TaskReminder.presetOneDayBeforeDue()]
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService(center: scheduler, now: { now })
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
    }

    func testCancelRemindersForTask_RemovesAnchoredNotificationIds() throws {
        let scheduler = MockNotificationScheduler()
        let task = TaskItem(notionPageId: "t-3", title: "Task")
        task.taskReminders = [
            TaskReminder.presetThirtyMinutesBeforeDue(),
            .explicitDate(ExplicitDateReminder(dateTime: referenceDate.addingTimeInterval(5000))),
        ]

        NotificationService(center: scheduler).cancelRemindersForTask(task)

        XCTAssertEqual(scheduler.removedIdentifiers.count, 2)
    }
}
