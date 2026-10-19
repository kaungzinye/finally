import XCTest
import SwiftData
import UserNotifications
@testable import Finally

@MainActor
final class Phase6BNotificationServiceTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 2_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testScheduleReminder_WithDeadlineReminder_SchedulesNotification() async throws {
        let ctx = try makeContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-1", title: "Buy milk")
        task.deadline = now.addingTimeInterval(7200)
        task.deadlineHasTime = true
        ctx.insert(task)

        let reminder = TaskReminder.deadline(DeadlineReminder(offset: .hourBefore))
        task.taskReminders = [reminder]
        try ctx.save()

        let service = NotificationService(center: scheduler, now: { now })
        service.rescheduleAllReminders(modelContext: ctx)
        await service.waitUntilIdle()

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        XCTAssertEqual(scheduler.addedRequests.first?.identifier, reminder.notificationId(for: task))
    }

    func testRescheduleAll_UsesTaskRemindersJSON() async throws {
        let ctx = try makeContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-2", title: "Future task")
        task.deadline = now.addingTimeInterval(2 * 86_400)
        task.deadlineHasTime = true
        task.taskReminders = [TaskReminder.deadline(DeadlineReminder(offset: .daysBefore(1)))]
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService(center: scheduler, now: { now })
        service.rescheduleAllReminders(modelContext: ctx)
        await service.waitUntilIdle()

        XCTAssertEqual(scheduler.addedRequests.count, 1)
    }

    func testCancelRemindersForTask_RemovesDeadlineAndExactNotificationIds() async throws {
        let scheduler = MockNotificationScheduler()
        let task = TaskItem(externalTaskID: "t-3", title: "Task")
        task.taskReminders = [
            TaskReminder.deadline(DeadlineReminder(offset: .hourBefore)),
            .exact(ExactReminder(at: referenceDate.addingTimeInterval(5000))),
        ]

        let service = NotificationService(center: scheduler)
        service.cancelRemindersForTask(task)
        await service.waitUntilIdle()

        XCTAssertEqual(scheduler.removedIdentifiers.count, 2)
    }
}
