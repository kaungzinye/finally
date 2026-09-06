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
        task.deadline = now.addingTimeInterval(3600)
        task.deadlineHasTime = true
        ctx.insert(task)

        let reminder = TaskReminder.presetThirtyMinutesBeforeDeadline()
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
        task.deadline = now.addingTimeInterval(-1800)
        ctx.insert(task)

        let reminder = TaskReminder.presetThirtyMinutesBeforeDeadline()
        task.taskReminders = [reminder]
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
    }

    func testNotificationBody_WhenDeadlineHasTime_ShowsDeadlineAtTime() throws {
        let task = TaskItem(externalTaskID: "t-body-time", title: "Meeting")
        task.deadline = referenceDate.addingTimeInterval(7200)
        task.deadlineHasTime = true

        let body = NotificationService().notificationBody(for: task, using: referenceDate)
        XCTAssertTrue(body.hasPrefix("Deadline at "))
    }

    func testNotificationBody_WhenDateOnlyAndDeadlineIsToday_ShowsDeadlineToday() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let task = TaskItem(externalTaskID: "t-body-today", title: "Grocery run")
        task.deadline = today
        task.deadlineHasTime = false

        let body = NotificationService().notificationBody(for: task, using: today)
        XCTAssertEqual(body, "Deadline today")
    }

    func testNotificationBody_WhenNoDeadline_ReturnsEmptyString() {
        let task = TaskItem(externalTaskID: "t-body-nil", title: "No date task")
        let body = NotificationService().notificationBody(for: task, using: referenceDate)
        XCTAssertEqual(body, "")
    }

    func testCancelRemindersForTask_RemovesAllIdentifiers() throws {
        let scheduler = MockNotificationScheduler()
        let task = TaskItem(externalTaskID: "t-cancel", title: "Cancel me")
        task.taskReminders = [
            TaskReminder.presetOneDayBeforeDeadline(),
            TaskReminder.presetThirtyMinutesBeforeDeadline(),
        ]

        makeService(scheduler: scheduler, now: referenceDate).cancelRemindersForTask(task)

        XCTAssertEqual(Set(scheduler.removedIdentifiers), Set(task.taskReminders.map(\.notificationId)))
    }

    func testRescheduleAll_WithOneValidReminder_SchedulesIt() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(externalTaskID: "t-reschedule", title: "Reschedule me")
        task.deadline = now.addingTimeInterval(2 * 86_400)
        task.deadlineHasTime = true
        task.taskReminders = [TaskReminder.presetOneDayBeforeDeadline()]
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
        task.deadline = now.addingTimeInterval(7200)
        task.status = .done
        task.taskReminders = [TaskReminder.presetOneDayBeforeDeadline()]
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
            task.deadline = now.addingTimeInterval(2 * 86_400 + Double(i + 1) * 3600)
            task.deadlineHasTime = true
            task.taskReminders = [TaskReminder.presetOneDayBeforeDeadline()]
            ctx.insert(task)
        }
        try ctx.save()

        makeService(scheduler: scheduler, now: now).rescheduleAllReminders(modelContext: ctx)
        XCTAssertEqual(scheduler.addedRequests.count, limit)
    }
}
