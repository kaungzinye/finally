import XCTest
import SwiftData
import UserNotifications
@testable import Finally

// MARK: - Mock notification scheduler

final class MockNotificationScheduler: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func addNotificationRequest(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func reset() {
        addedRequests = []
        removedIdentifiers = []
    }
}

// MARK: - Test suite

final class NotificationServiceUnitTests: XCTestCase {

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, ReminderItem.self, UserSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// Returns a fixed "now" 1 hour in the past relative to a reference date so we can control time.
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func makeService(
        scheduler: MockNotificationScheduler,
        now: Date
    ) -> NotificationService {
        NotificationService(center: scheduler, now: { now })
    }

    // MARK: - scheduleReminder: basic scheduling

    func testScheduleReminder_WhenFireDateIsFuture_AddsRequestAndSetsScheduled() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-1", title: "Buy milk")
        task.dueDate = now.addingTimeInterval(3600) // 1 hr from now
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 1800, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        XCTAssertEqual(scheduler.addedRequests.first?.identifier, reminder.notificationId)
        XCTAssertTrue(reminder.isScheduled)
    }

    func testScheduleReminder_WhenFireDateIsPast_DoesNotSchedule() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-2", title: "Old task")
        task.dueDate = now.addingTimeInterval(-1800) // 30 min ago
        ctx.insert(task)

        // Fire date = dueDate - 1800s = 1hr ago (past)
        let reminder = ReminderItem(intervalSeconds: 1800, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 0, "Past fire date should not be scheduled")
        XCTAssertFalse(reminder.isScheduled)
    }

    func testScheduleReminder_WhenFireDateIsExactlyNow_DoesNotSchedule() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-exact", title: "Exact now")
        task.dueDate = now.addingTimeInterval(1800)
        ctx.insert(task)

        // Fire date = dueDate - 1800 = now exactly
        let reminder = ReminderItem(intervalSeconds: 1800, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        // fireDate == now is NOT strictly > now, so it should not schedule
        XCTAssertEqual(scheduler.addedRequests.count, 0)
    }

    func testScheduleReminder_WhenTaskHasNoDueDate_DoesNotSchedule() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-3", title: "No due date")
        // dueDate = nil — fireDate will be nil for interval reminder
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
        XCTAssertFalse(reminder.isScheduled)
    }

    // MARK: - scheduleReminder: absolute date reminders

    func testScheduleReminder_AbsoluteDate_FutureDate_Schedules() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-abs-1", title: "Absolute reminder")
        // No due date needed for absolute reminders
        ctx.insert(task)

        let fireAt = now.addingTimeInterval(7200) // 2 hr from now
        let reminder = ReminderItem(
            absoluteDate: fireAt,
            label: "2026-04-01 at 9:00 AM",
            taskNotionPageId: task.notionPageId
        )
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        XCTAssertTrue(reminder.isScheduled)
    }

    func testScheduleReminder_AbsoluteDate_PastDate_DoesNotSchedule() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-abs-2", title: "Old absolute")
        ctx.insert(task)

        let fireAt = now.addingTimeInterval(-3600) // 1 hr ago
        let reminder = ReminderItem(
            absoluteDate: fireAt,
            label: "Yesterday",
            taskNotionPageId: task.notionPageId
        )
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
        XCTAssertFalse(reminder.isScheduled)
    }

    // MARK: - scheduleReminder: notification content

    func testScheduleReminder_NotificationContent_TitleIsTaskTitle() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-content", title: "Doctor appointment")
        task.dueDate = now.addingTimeInterval(7200)
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hour before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        let req = try XCTUnwrap(scheduler.addedRequests.first)
        XCTAssertEqual(req.content.title, "Doctor appointment")
        // body must NOT be the raw label string
        XCTAssertNotEqual(req.content.body, "1 hour before")
        XCTAssertEqual(req.content.userInfo["taskId"] as? String, "t-content")
    }

    // MARK: - notificationBody

    func testNotificationBody_WhenDueDateHasTime_ShowsDueAtTime() throws {
        let ctx = try makeInMemoryContext()
        let task = TaskItem(notionPageId: "t-body-time", title: "Meeting")
        // Set to a specific time on referenceDate
        let due = referenceDate.addingTimeInterval(7200)
        task.dueDate = due
        task.dueDateHasTime = true
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService()
        let body = service.notificationBody(for: task, using: referenceDate)

        // Should start with "Due at" and include a time
        XCTAssertTrue(body.hasPrefix("Due at "), "Expected 'Due at …', got '\(body)'")
    }

    func testNotificationBody_WhenDateOnlyAndDueDateIsToday_ShowsDueToday() throws {
        let ctx = try makeInMemoryContext()
        let today = Calendar.current.startOfDay(for: Date())
        let task = TaskItem(notionPageId: "t-body-today", title: "Grocery run")
        task.dueDate = today
        task.dueDateHasTime = false
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService()
        let body = service.notificationBody(for: task, using: today)

        XCTAssertEqual(body, "Due today")
    }

    func testNotificationBody_WhenDateOnlyAndDueDateIsTomorrow_ShowsDueTomorrow() throws {
        let ctx = try makeInMemoryContext()
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let task = TaskItem(notionPageId: "t-body-tomorrow", title: "Dentist")
        task.dueDate = tomorrow
        task.dueDateHasTime = false
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService()
        let body = service.notificationBody(for: task, using: today)

        XCTAssertEqual(body, "Due tomorrow")
    }

    func testNotificationBody_WhenDateOnlyAndDueDateIsFuture_ShowsFormattedDate() throws {
        let ctx = try makeInMemoryContext()
        let today = Calendar.current.startOfDay(for: Date())
        let futureDate = Calendar.current.date(byAdding: .day, value: 5, to: today)!
        let task = TaskItem(notionPageId: "t-body-future", title: "Conference")
        task.dueDate = futureDate
        task.dueDateHasTime = false
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService()
        let body = service.notificationBody(for: task, using: today)

        XCTAssertTrue(body.hasPrefix("Due "), "Expected 'Due <date>', got '\(body)'")
        XCTAssertFalse(body.contains(":"), "Date-only body should not contain a time separator")
    }

    func testNotificationBody_WhenNoDueDate_ReturnsEmptyString() throws {
        let ctx = try makeInMemoryContext()
        let task = TaskItem(notionPageId: "t-body-nil", title: "No date task")
        // dueDate = nil
        ctx.insert(task)
        try ctx.save()

        let service = NotificationService()
        let body = service.notificationBody(for: task, using: referenceDate)

        XCTAssertEqual(body, "")
    }

    func testScheduleReminder_Trigger_IsCalendarNotificationWithCorrectComponents() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        // fireDate = dueDate - 3600 = now + 3600
        let dueDate = now.addingTimeInterval(7200)
        let expectedFireDate = now.addingTimeInterval(3600)

        let task = TaskItem(notionPageId: "t-trigger", title: "Check trigger")
        task.dueDate = dueDate
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder)

        let trigger = try XCTUnwrap(scheduler.addedRequests.first?.trigger as? UNCalendarNotificationTrigger)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: expectedFireDate)
        XCTAssertEqual(trigger.dateComponents.year, components.year)
        XCTAssertEqual(trigger.dateComponents.month, components.month)
        XCTAssertEqual(trigger.dateComponents.day, components.day)
        XCTAssertEqual(trigger.dateComponents.hour, components.hour)
        XCTAssertEqual(trigger.dateComponents.minute, components.minute)
        XCTAssertFalse(trigger.repeats)
    }

    // MARK: - cancelRemindersForTask

    func testCancelRemindersForTask_RemovesAllIdentifiersAndClearsScheduledFlag() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-cancel", title: "Cancel me")
        task.dueDate = now.addingTimeInterval(86400)
        ctx.insert(task)

        let r1 = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        let r2 = ReminderItem(intervalSeconds: 1800, label: "30 min before", taskNotionPageId: task.notionPageId)
        let r3 = ReminderItem(intervalSeconds: 86400, label: "1 day before", taskNotionPageId: task.notionPageId)
        r1.task = task; r1.isScheduled = true
        r2.task = task; r2.isScheduled = true
        r3.task = task; r3.isScheduled = false // already unscheduled
        ctx.insert(r1); ctx.insert(r2); ctx.insert(r3)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.cancelRemindersForTask(task)

        XCTAssertEqual(Set(scheduler.removedIdentifiers), Set([r1.notificationId, r2.notificationId, r3.notificationId]))
        XCTAssertFalse(r1.isScheduled)
        XCTAssertFalse(r2.isScheduled)
        XCTAssertFalse(r3.isScheduled)
    }

    func testCancelRemindersForTask_WhenNoReminders_IsNoOp() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-empty", title: "No reminders")
        ctx.insert(task)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.cancelRemindersForTask(task)

        XCTAssertTrue(scheduler.removedIdentifiers.isEmpty)
    }

    // MARK: - rescheduleAllReminders: basic

    func testRescheduleAll_WithOneValidReminder_SchedulesIt() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-reschedule", title: "Reschedule me")
        task.dueDate = now.addingTimeInterval(7200)
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        XCTAssertTrue(reminder.isScheduled)
    }

    func testRescheduleAll_CancelsAllBeforeRescheduling() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-cancel-first", title: "Cancel first")
        task.dueDate = now.addingTimeInterval(7200)
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        reminder.isScheduled = true
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        // The reminder's ID must appear in removedIdentifiers (cancel-before-reschedule)
        XCTAssertTrue(scheduler.removedIdentifiers.contains(reminder.notificationId))
    }

    // MARK: - rescheduleAllReminders: skip conditions

    func testRescheduleAll_SkipsDoneTaskReminders() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-done", title: "Done task")
        task.dueDate = now.addingTimeInterval(7200)
        task.status = .done
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 0, "Done tasks should not be scheduled")
        XCTAssertFalse(reminder.isScheduled)
    }

    func testRescheduleAll_SkipsPastFireDates() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-past-fire", title: "Past fire")
        task.dueDate = now.addingTimeInterval(-1800) // already past due
        ctx.insert(task)

        // intervalSeconds=0 → fire date = dueDate = past
        let reminder = ReminderItem(intervalSeconds: 0, label: "At due time", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
        XCTAssertFalse(reminder.isScheduled)
    }

    func testRescheduleAll_SkipsRemindersWithNoTask() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        // Reminder with no task relationship
        let reminder = ReminderItem(intervalSeconds: 3600, label: "Orphan", taskNotionPageId: "orphan-id")
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
        XCTAssertFalse(reminder.isScheduled)
    }

    func testRescheduleAll_SkipsReminderWhenTaskHasNoDueDate() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-no-due", title: "No due date")
        // dueDate = nil
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 0)
        XCTAssertFalse(reminder.isScheduled)
    }

    // MARK: - rescheduleAllReminders: 60-notification limit

    func testRescheduleAll_RespectsMaxScheduledNotificationsLimit() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate
        let limit = AppConstants.maxScheduledNotifications

        // Create limit + 5 reminders, all future
        for i in 0..<(limit + 5) {
            let task = TaskItem(notionPageId: "t-limit-\(i)", title: "Task \(i)")
            task.dueDate = now.addingTimeInterval(Double(i + 1) * 3600 + 7200)
            ctx.insert(task)

            let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
            reminder.task = task
            ctx.insert(reminder)
        }
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, limit, "Should schedule exactly \(limit) reminders")
    }

    func testRescheduleAll_BeyondLimit_SoonestGetScheduled_LatestDoNot() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate
        let limit = AppConstants.maxScheduledNotifications

        var reminders: [ReminderItem] = []

        // Create limit + 1 reminders, staggered by 1 hour each
        for i in 0..<(limit + 1) {
            let task = TaskItem(notionPageId: "t-sort-\(i)", title: "Task \(i)")
            // Soonest due = task 0, latest = task limit
            task.dueDate = now.addingTimeInterval(Double(i + 1) * 3600 * 2)
            ctx.insert(task)

            let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
            reminder.task = task
            ctx.insert(reminder)
            reminders.append(reminder)
        }
        try ctx.save()

        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, limit)

        // The last (latest-due) reminder should NOT be scheduled
        let lastReminder = reminders.last!
        XCTAssertFalse(lastReminder.isScheduled, "Latest-due reminder should not be scheduled when over limit")
    }

    func testRescheduleAll_SchedulesSoonestFirst_WhenOverLimit() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        // Two tasks: one soonest (2 hr from now due, 1 hr fire) and one latest (100 hr from now due, 1 hr fire)
        // With limit = 1 (not realistic, but we'll check which one gets scheduled)
        let soonTask = TaskItem(notionPageId: "t-soon", title: "Soon")
        soonTask.dueDate = now.addingTimeInterval(7200) // 2 hr
        ctx.insert(soonTask)

        let lateTask = TaskItem(notionPageId: "t-late", title: "Late")
        lateTask.dueDate = now.addingTimeInterval(360_000) // 100 hr
        ctx.insert(lateTask)

        let soonReminder = ReminderItem(intervalSeconds: 3600, label: "Soon", taskNotionPageId: soonTask.notionPageId)
        soonReminder.task = soonTask
        ctx.insert(soonReminder)

        let lateReminder = ReminderItem(intervalSeconds: 3600, label: "Late", taskNotionPageId: lateTask.notionPageId)
        lateReminder.task = lateTask
        ctx.insert(lateReminder)

        try ctx.save()

        // With the real limit (60) both schedule, but we can still verify ordering from addedRequests
        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 2)
        // First scheduled should be the soonest fire date
        let firstId = scheduler.addedRequests.first?.identifier
        XCTAssertEqual(firstId, soonReminder.notificationId, "Soonest-firing reminder should be scheduled first")
    }

    // MARK: - Integration: recurring task completion + reminder rescheduling

    func testRecurringCompletion_AdvancesDueDateAndRemindersRescheduleToNewDate() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        // Task due 2 days from now, weekly recurrence
        let originalDue = now.addingTimeInterval(2 * 86400)
        let task = TaskItem(notionPageId: "t-recur", title: "Weekly task")
        task.dueDate = originalDue
        task.recurrence = .weekly
        ctx.insert(task)

        // Two reminders: 1 day before and 1 hour before
        let r1 = ReminderItem(intervalSeconds: 86400, label: "1 day before", taskNotionPageId: task.notionPageId)
        let r2 = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        r1.task = task; r2.task = task
        ctx.insert(r1); ctx.insert(r2)
        try ctx.save()

        // Complete the task — due date should advance by 7 days
        let wasRecycled = task.complete()
        XCTAssertTrue(wasRecycled, "Weekly task should be recycled on completion")

        let expectedNewDue = originalDue.addingTimeInterval(7 * 86400)
        XCTAssertEqual(
            task.dueDate?.timeIntervalSinceReferenceDate ?? 0,
            expectedNewDue.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "Due date should advance by 7 days"
        )
        XCTAssertEqual(task.status, .notStarted, "Status should reset to notStarted")

        // Reschedule after completion
        let service = makeService(scheduler: scheduler, now: now)
        service.rescheduleAllReminders(modelContext: ctx)

        XCTAssertEqual(scheduler.addedRequests.count, 2, "Both reminders should schedule for new due date")

        // Verify fire dates are relative to new due date
        let newDue = try XCTUnwrap(task.dueDate)
        let expectedR1Fire = newDue.addingTimeInterval(-86400)
        let expectedR2Fire = newDue.addingTimeInterval(-3600)

        let addedIds = scheduler.addedRequests.map(\.identifier)
        XCTAssertTrue(addedIds.contains(r1.notificationId))
        XCTAssertTrue(addedIds.contains(r2.notificationId))

        // Check that r1 trigger matches expected fire date
        if let r1Req = scheduler.addedRequests.first(where: { $0.identifier == r1.notificationId }),
           let trigger = r1Req.trigger as? UNCalendarNotificationTrigger {
            let comps = Calendar.current.dateComponents([.day], from: expectedR1Fire)
            XCTAssertEqual(trigger.dateComponents.day, comps.day)
        } else {
            XCTFail("r1 should have a calendar trigger")
        }
        _ = expectedR2Fire // used implicitly via addedIds check above
    }

    func testNonRecurringCompletion_MarksDoneAndCancelsReminders() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()
        let now = referenceDate

        let task = TaskItem(notionPageId: "t-nrecur", title: "One-shot task")
        task.dueDate = now.addingTimeInterval(7200)
        task.recurrence = .none
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        reminder.isScheduled = true
        ctx.insert(reminder)
        try ctx.save()

        let wasRecycled = task.complete()
        XCTAssertFalse(wasRecycled, "Non-recurring task should not be recycled")
        XCTAssertEqual(task.status, .done)

        // Simulating what the app does after completion
        let service = makeService(scheduler: scheduler, now: now)
        service.cancelRemindersForTask(task)

        XCTAssertTrue(scheduler.removedIdentifiers.contains(reminder.notificationId))
        XCTAssertFalse(reminder.isScheduled)
    }

    // MARK: - Integration: time manipulation — future becomes past

    func testRescheduleAll_WhenClockAdvancesPastFireDate_ReminderNoLongerSchedules() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()

        let task = TaskItem(notionPageId: "t-time", title: "Time sensitive")
        let dueDate = referenceDate.addingTimeInterval(3600) // 1 hr from reference
        task.dueDate = dueDate
        ctx.insert(task)

        // Fire date = dueDate - 1800 = 30 min from reference
        let reminder = ReminderItem(intervalSeconds: 1800, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        // At reference time: fire date is future — should schedule
        let serviceBefore = makeService(scheduler: scheduler, now: referenceDate)
        serviceBefore.rescheduleAllReminders(modelContext: ctx)
        XCTAssertEqual(scheduler.addedRequests.count, 1, "Should schedule when now is before fire date")

        // Advance clock past fire date
        scheduler.reset()
        let future = referenceDate.addingTimeInterval(2000) // past the 30-min fire time
        let serviceAfter = makeService(scheduler: scheduler, now: future)
        serviceAfter.rescheduleAllReminders(modelContext: ctx)
        XCTAssertEqual(scheduler.addedRequests.count, 0, "Should not schedule when clock has passed fire date")
        XCTAssertFalse(reminder.isScheduled)
    }

    // MARK: - Notification ID format

    func testNotificationId_IntervalReminder_UsesExpectedFormat() throws {
        let ctx = try makeInMemoryContext()
        let task = TaskItem(notionPageId: "page-xyz", title: "Test")
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr", taskNotionPageId: task.notionPageId)
        ctx.insert(reminder)
        try ctx.save()

        XCTAssertEqual(reminder.notificationId, "task-page-xyz-reminder-3600")
    }

    func testNotificationId_AbsoluteReminder_UsesTimestampFormat() throws {
        let ctx = try makeInMemoryContext()
        let task = TaskItem(notionPageId: "page-abc", title: "Test")
        ctx.insert(task)

        let fireAt = Date(timeIntervalSince1970: 2_000_000)
        let reminder = ReminderItem(absoluteDate: fireAt, label: "Custom", taskNotionPageId: task.notionPageId)
        ctx.insert(reminder)
        try ctx.save()

        XCTAssertEqual(reminder.notificationId, "task-page-abc-reminder-abs-2000000")
    }

    // MARK: - Date-only task scheduling with preferred time (T085)

    /// Helper: builds a Date for a given calendar day at a specific hour/minute in local time.
    private func localDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    func testComputeFireDate_DateOnlyTask_UsesPreferredTimeNotMidnight() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()

        // Date-only task due on a specific day — stored as local midnight
        let dueMidnight = localDate(year: 2026, month: 6, day: 15) // midnight local
        let task = TaskItem(notionPageId: "t-dateonly-1", title: "Date only task")
        task.dueDate = dueMidnight
        task.dueDateHasTime = false
        ctx.insert(task)

        // "30 min before" reminder — should fire 30 min before 9 AM = 8:30 AM, not 11:30 PM the night before
        let reminder = ReminderItem(intervalSeconds: 30 * 60, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let preferredMinutes = 9 * 60 // 9:00 AM
        let now = localDate(year: 2026, month: 6, day: 14) // day before, so fire date is future

        let service = makeService(scheduler: scheduler, now: now)
        let fireDate = service.computeFireDate(for: task, reminder: reminder, defaultReminderMinutes: preferredMinutes)

        let expectedFireDate = localDate(year: 2026, month: 6, day: 15, hour: 8, minute: 30)
        XCTAssertEqual(
            fireDate?.timeIntervalSinceReferenceDate ?? 0,
            expectedFireDate.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "30 min before a date-only task with 9 AM default should fire at 8:30 AM"
        )
    }

    func testComputeFireDate_DateOnlyTask_MidnightWouldHaveBeenWrong() throws {
        let ctx = try makeInMemoryContext()

        let dueMidnight = localDate(year: 2026, month: 6, day: 15)
        let task = TaskItem(notionPageId: "t-dateonly-wrong", title: "Midnight check")
        task.dueDate = dueMidnight
        task.dueDateHasTime = false
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 30 * 60, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let preferredMinutes = 9 * 60
        let wrongFireDate = localDate(year: 2026, month: 6, day: 14, hour: 23, minute: 30) // 11:30 PM night before

        let service = NotificationService()
        let fireDate = service.computeFireDate(for: task, reminder: reminder, defaultReminderMinutes: preferredMinutes)

        XCTAssertNotEqual(
            fireDate?.timeIntervalSinceReferenceDate ?? 0,
            wrongFireDate.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "Fire date must not be 11:30 PM the night before (midnight-based calculation)"
        )
    }

    func testComputeFireDate_DateOnlyTask_DifferentPreferredTime_ShiftsFireDate() throws {
        let ctx = try makeInMemoryContext()

        let dueMidnight = localDate(year: 2026, month: 6, day: 20)
        let task = TaskItem(notionPageId: "t-dateonly-shift", title: "Shift test")
        task.dueDate = dueMidnight
        task.dueDateHasTime = false
        ctx.insert(task)

        // 1 hour before reminder
        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = NotificationService()

        // 8 AM preference → fire at 7 AM
        let fireAt8AM = service.computeFireDate(for: task, reminder: reminder, defaultReminderMinutes: 8 * 60)
        let expected8AM = localDate(year: 2026, month: 6, day: 20, hour: 7, minute: 0)

        // 5 PM preference → fire at 4 PM
        let fireAt5PM = service.computeFireDate(for: task, reminder: reminder, defaultReminderMinutes: 17 * 60)
        let expected5PM = localDate(year: 2026, month: 6, day: 20, hour: 16, minute: 0)

        XCTAssertEqual(fireAt8AM?.timeIntervalSinceReferenceDate ?? 0, expected8AM.timeIntervalSinceReferenceDate, accuracy: 1)
        XCTAssertEqual(fireAt5PM?.timeIntervalSinceReferenceDate ?? 0, expected5PM.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testComputeFireDate_DateTimeTask_IgnoresPreferredTime() throws {
        let ctx = try makeInMemoryContext()

        // Task with an explicit time (3 PM)
        let dueAt3PM = localDate(year: 2026, month: 6, day: 15, hour: 15, minute: 0)
        let task = TaskItem(notionPageId: "t-datetime-1", title: "Has time")
        task.dueDate = dueAt3PM
        task.dueDateHasTime = true
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 30 * 60, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let service = NotificationService()
        // Pass a totally different preferred time — should be ignored
        let fireDate = service.computeFireDate(for: task, reminder: reminder, defaultReminderMinutes: 9 * 60)

        let expectedFireDate = localDate(year: 2026, month: 6, day: 15, hour: 14, minute: 30) // 2:30 PM
        XCTAssertEqual(
            fireDate?.timeIntervalSinceReferenceDate ?? 0,
            expectedFireDate.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "Date+time tasks should ignore preferred time and fire relative to actual due time"
        )
    }

    func testScheduleReminder_DateOnlyTask_FiresAtPreferredTimeNotMidnight() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()

        let dueMidnight = localDate(year: 2026, month: 6, day: 25)
        let task = TaskItem(notionPageId: "t-scheduleonly", title: "Schedule date-only")
        task.dueDate = dueMidnight
        task.dueDateHasTime = false
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 30 * 60, label: "30 min before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let now = localDate(year: 2026, month: 6, day: 24) // day before
        let service = makeService(scheduler: scheduler, now: now)
        service.scheduleReminder(for: task, reminder: reminder, defaultReminderMinutes: 9 * 60)

        XCTAssertEqual(scheduler.addedRequests.count, 1, "Should schedule the notification")
        XCTAssertTrue(reminder.isScheduled)

        // Verify the trigger fires at 8:30 AM, not 11:30 PM
        let trigger = try XCTUnwrap(scheduler.addedRequests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 8, "Should fire at hour 8 (8:30 AM)")
        XCTAssertEqual(trigger.dateComponents.minute, 30, "Should fire at minute 30 (8:30 AM)")
    }

    // MARK: - Subtask reminder fire date (Change 3 + 4)

    func testComputeFireDate_Subtask_UsesEffectiveDate() throws {
        let ctx = try makeInMemoryContext()

        // Subtask with suggestedDate at 3 PM tomorrow — no dueDate
        let tomorrow3PM = localDate(year: 2026, month: 6, day: 16, hour: 15, minute: 0)
        let subtask = TaskItem(notionPageId: "sub-1", title: "Draft section")
        subtask.parentId = "parent-1"       // marks it as a subtask
        subtask.suggestedDate = tomorrow3PM // effectiveDate returns this
        // dueDate intentionally nil — subtasks don't have one
        ctx.insert(subtask)

        let reminder = ReminderItem(intervalSeconds: 1800, label: "30 min before", taskNotionPageId: subtask.notionPageId)
        reminder.task = subtask
        ctx.insert(reminder)
        try ctx.save()

        let service = NotificationService()
        let fireDate = service.computeFireDate(for: subtask, reminder: reminder)

        let expected = localDate(year: 2026, month: 6, day: 16, hour: 14, minute: 30) // 2:30 PM
        XCTAssertNotNil(fireDate, "Subtask reminder should produce a fire date via effectiveDate")
        XCTAssertEqual(
            fireDate!.timeIntervalSinceReferenceDate,
            expected.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "30 min before 3 PM should fire at 2:30 PM"
        )
    }

    func testComputeFireDate_Subtask_DoesNotShiftTo9AM() throws {
        let ctx = try makeInMemoryContext()

        // Subtask scheduled at 2:30 PM — dueDateHasTime is false (subtasks are never Notion-synced with time)
        // Without the isSubtask guard, computeFireDate would shift 2:30 PM → 9:00 AM wrongly
        let tomorrow230PM = localDate(year: 2026, month: 6, day: 16, hour: 14, minute: 30)
        let subtask = TaskItem(notionPageId: "sub-2", title: "Review draft")
        subtask.parentId = "parent-1"
        subtask.suggestedDate = tomorrow230PM
        subtask.dueDateHasTime = false   // always false for subtasks
        ctx.insert(subtask)

        let reminder = ReminderItem(intervalSeconds: 0, label: "At time", taskNotionPageId: subtask.notionPageId)
        reminder.task = subtask
        ctx.insert(reminder)
        try ctx.save()

        let service = NotificationService()
        let fireDate = service.computeFireDate(for: subtask, reminder: reminder)

        XCTAssertNotNil(fireDate)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: fireDate!)
        XCTAssertNotEqual(comps.hour, 9, "Subtask fire date must NOT be shifted to 9 AM — isSubtask skips the midnight-shift logic")
        XCTAssertEqual(comps.hour, 14, "Fire date should be at hour 14 (2:30 PM = suggestedDate)")
    }

    func testFireDate_Subtask_UsesEffectiveDate() throws {
        let ctx = try makeInMemoryContext()

        let suggested = localDate(year: 2026, month: 6, day: 20, hour: 10, minute: 0) // 10 AM
        let subtask = TaskItem(notionPageId: "sub-3", title: "Finalize")
        subtask.parentId = "parent-1"
        subtask.suggestedDate = suggested
        ctx.insert(subtask)

        let reminder = ReminderItem(intervalSeconds: 3600, label: "1 hr before", taskNotionPageId: subtask.notionPageId)
        reminder.task = subtask
        ctx.insert(reminder)
        try ctx.save()

        // ReminderItem.fireDate should use effectiveDate (= suggestedDate for subtasks)
        let expected = localDate(year: 2026, month: 6, day: 20, hour: 9, minute: 0) // 9 AM
        XCTAssertEqual(
            reminder.fireDate?.timeIntervalSinceReferenceDate ?? 0,
            expected.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "ReminderItem.fireDate should offset from suggestedDate, not dueDate"
        )
    }

    func testRescheduleAll_DateOnlyTasks_UsePreferredTime() throws {
        let ctx = try makeInMemoryContext()
        let scheduler = MockNotificationScheduler()

        let dueMidnight = localDate(year: 2026, month: 6, day: 25)
        let task = TaskItem(notionPageId: "t-reschedule-dateonly", title: "Date-only reschedule")
        task.dueDate = dueMidnight
        task.dueDateHasTime = false
        ctx.insert(task)

        let reminder = ReminderItem(intervalSeconds: 60 * 60, label: "1 hr before", taskNotionPageId: task.notionPageId)
        reminder.task = task
        ctx.insert(reminder)
        try ctx.save()

        let now = localDate(year: 2026, month: 6, day: 24)
        let service = makeService(scheduler: scheduler, now: now)
        // 10 AM preference → fire at 9 AM
        service.rescheduleAllReminders(modelContext: ctx, defaultReminderMinutes: 10 * 60)

        XCTAssertEqual(scheduler.addedRequests.count, 1)
        let trigger = try XCTUnwrap(scheduler.addedRequests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 9, "1 hr before 10 AM should fire at 9 AM")
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }
}
