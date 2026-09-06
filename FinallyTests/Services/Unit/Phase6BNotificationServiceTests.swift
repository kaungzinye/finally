import XCTest
import SwiftData
import UserNotifications
@testable import Finally

final class Phase6BNotificationServiceTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 2_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testScheduleReminder_WithAnchoredTaskReminder_SchedulesNotification() throws {
        let ctx = try makeContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-1", title: "Buy milk")
        task.deadline = now.addingTimeInterval(3600)
        task.deadlineHasTime = true
        ctx.insert(task)

        let reminder = TaskReminder.presetThirtyMinutesBeforeDeadline()
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

        let task = TaskItem(externalTaskID: "t-2", title: "Future task")
        task.deadline = now.addingTimeInterval(2 * 86_400)
        task.deadlineHasTime = true
        task.taskReminders = [TaskReminder.presetOneDayBeforeDeadline()]
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService(center: scheduler, now: { now })
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
    }

    func testCancelRemindersForTask_RemovesAnchoredNotificationIds() throws {
        let scheduler = MockNotificationScheduler()
        let task = TaskItem(externalTaskID: "t-3", title: "Task")
        task.taskReminders = [
            TaskReminder.presetThirtyMinutesBeforeDeadline(),
            .explicitDate(ExplicitDateReminder(dateTime: referenceDate.addingTimeInterval(5000))),
        ]

        NotificationService(center: scheduler).cancelRemindersForTask(task)

        XCTAssertEqual(scheduler.removedIdentifiers.count, 2)
    }
}
