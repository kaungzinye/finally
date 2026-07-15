import XCTest
import SwiftData
import UserNotifications
@testable import Finally

final class NotificationServiceUnitTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func makeService(scheduler: MockNotificationScheduler, now: Date) -> NotificationService {
        NotificationService(center: scheduler, now: { now })
    }

    func testScheduleReminder_WhenFireDateIsFuture_AddsRequest() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-1", title: "Buy milk")
        task.dueDate = now.addingTimeInterval(3600)
        task.dueDateHasTime = true
        ctx.insert(task)

        let reminder = TaskReminder.presetThirtyMinutesBeforeDue()
        task.taskReminders = [reminder]
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        XCTAssertEqual(scheduler.addedRequests.first?.identifier, reminder.notificationId)
    }

    func testScheduleReminder_WhenFireDateIsPast_DoesNotSchedule() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-2", title: "Old task")
        task.dueDate = now.addingTimeInterval(-1800)
        ctx.insert(task)

        let reminder = TaskReminder.presetThirtyMinutesBeforeDue()
        task.taskReminders = [reminder]
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
    }

    func testNotificationBody_WhenDueDateHasTime_ShowsDueAtTime() throws {
        let task = TaskItem(externalTaskID: "t-body-time", title: "Meeting")
        task.dueDate = referenceDate.addingTimeInterval(7200)
        task.dueDateHasTime = true

        let body = NotificationService().notificationBody(for: task, using: referenceDate)
        XCTAssertTrue(body.hasPrefix("Due at "))
    }

    func testNotificationBody_WhenDateOnlyAndDueDateIsToday_ShowsDueToday() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let task = TaskItem(externalTaskID: "t-body-today", title: "Grocery run")
        task.dueDate = today
        task.dueDateHasTime = false

        let body = NotificationService().notificationBody(for: task, using: today)
        XCTAssertEqual(body, "Due today")
    }

    func testNotificationBody_WhenNoDueDate_ReturnsEmptyString() {
        let task = TaskItem(externalTaskID: "t-body-nil", title: "No date task")
        let body = NotificationService().notificationBody(for: task, using: referenceDate)
        XCTAssertEqual(body, "")
    }

    func testCancelRemindersForTask_RemovesAllIdentifiers() throws {
        let scheduler = MockNotificationScheduler()
        let task = TaskItem(externalTaskID: "t-cancel", title: "Cancel me")
        task.taskReminders = [
            TaskReminder.presetOneDayBeforeDue(),
            TaskReminder.presetThirtyMinutesBeforeDue(),
        ]

        makeService(scheduler: scheduler, now: referenceDate).cancelRemindersForTask(task)

        XCTAssertEqual(Set(scheduler.removedIdentifiers), Set(task.taskReminders.map(\.notificationId)))
    }

    func testRescheduleAll_WithOneValidReminder_SchedulesIt() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-reschedule", title: "Reschedule me")
        task.dueDate = now.addingTimeInterval(2 * 86_400)
        task.dueDateHasTime = true
        task.taskReminders = [TaskReminder.presetOneDayBeforeDue()]
        ctx.insert(task)
        try ctx.save()

        makeService(scheduler: scheduler, now: now).rescheduleAllReminders(modelContext: ctx)
        XCTAssertEqual(scheduler.addedRequests.count, 1)
    }

    func testRescheduleAll_SkipsDoneTasks() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-done", title: "Done task")
        task.dueDate = now.addingTimeInterval(7200)
        task.status = .done
        task.taskReminders = [TaskReminder.presetOneDayBeforeDue()]
        ctx.insert(task)
        try ctx.save()

        makeService(scheduler: scheduler, now: now).rescheduleAllReminders(modelContext: ctx)
        XCTAssertEqual(scheduler.addedRequests.count, 0)
    }

    func testRescheduleAll_RespectsMaxScheduledNotificationsLimit() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate
        let limit = AppConstants.maxScheduledNotifications

        for i in 0..<(limit + 5) {
            let task = TaskItem(externalTaskID: "t-limit-\(i)", title: "Task \(i)")
            task.dueDate = now.addingTimeInterval(2 * 86_400 + Double(i + 1) * 3600)
            task.dueDateHasTime = true
            task.taskReminders = [TaskReminder.presetOneDayBeforeDue()]
            ctx.insert(task)
        }
        try ctx.save()

        makeService(scheduler: scheduler, now: now).rescheduleAllReminders(modelContext: ctx)
        XCTAssertEqual(scheduler.addedRequests.count, limit)
    }
}
