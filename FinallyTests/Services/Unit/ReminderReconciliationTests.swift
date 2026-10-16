import XCTest
import SwiftData
import UserNotifications
@testable import Finally

@MainActor
final class ReminderReconciliationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func task(_ id: String, after seconds: Double, store: ModelContext) -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: id)
        task.providerWorkspaceId = "server"
        task.deadline = now.addingTimeInterval(seconds + 3600)
        task.deadlineHasTime = true
        task.taskReminders = [.deadline(DeadlineReminder(offset: .hourBefore))]
        store.insert(task)
        return task
    }

    func testBudgetPreservesOtherMomentsAndQueuesFarRulesThroughRelaunch() async throws {
        let store = try context()
        let center = MockNotificationScheduler()
        for i in 0..<62 {
            center.pending["moment-\(i)"] = UNNotificationRequest(identifier: "moment-\(i)", content: UNMutableNotificationContent(), trigger: nil)
        }
        let far = task("far", after: 600, store: store)
        let near = task("near", after: 60, store: store)
        let middle = task("middle", after: 120, store: store)
        try store.save()
        var service = NotificationService(center: center, now: { self.now })
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertEqual(center.addedRequests.map(\.identifier), [near.taskReminders[0].notificationId(for: near), middle.taskReminders[0].notificationId(for: middle)])
        XCTAssertEqual(service.deferredCount, 1)
        XCTAssertEqual(center.pending.count, 64)
        XCTAssertEqual(far.taskReminders.count, 1)

        near.status = .done
        service = NotificationService(center: center, now: { self.now })
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertNil(center.pending[near.taskReminders[0].notificationId(for: near)])
        XCTAssertNotNil(center.pending[far.taskReminders[0].notificationId(for: far)])
        XCTAssertEqual(service.deferredCount, 0)
        XCTAssertEqual(center.pending.keys.filter { $0.hasPrefix("moment-") }.count, 62)
    }

    func testOfflineCompletionReplenishesFromCallerContext() async throws {
        let store = try context()
        let center = MockNotificationScheduler()
        for i in 0..<63 {
            center.pending["moment-\(i)"] = UNNotificationRequest(identifier: "moment-\(i)", content: UNMutableNotificationContent(), trigger: nil)
        }
        let first = task("first", after: 60, store: store)
        let second = task("second", after: 120, store: store)
        try store.save()
        let service = NotificationService(center: center, now: { self.now })
        service.rescheduleAllReminders(modelContext: store, defaultReminderMinutes: 9 * 60)
        await service.waitUntilIdle()
        let caller = ModelContext(store.container)
        let completed = try XCTUnwrap(caller.fetch(FetchDescriptor<TaskItem>()).first { $0.externalTaskID == first.externalTaskID })
        completed.status = .done
        service.cancelRemindersForTask(completed, modelContext: caller)
        await service.waitUntilIdle()
        XCTAssertNil(center.pending[first.taskReminders[0].notificationId(for: first)])
        XCTAssertNotNil(center.pending[second.taskReminders[0].notificationId(for: second)])
        XCTAssertEqual(service.deferredCount, 0)
    }

    func testFailureAndSilentRejectionKeepRulesVisibleAndRetryable() async throws {
        let store = try context()
        let task = task("retry", after: 60, store: store)
        let center = MockNotificationScheduler()
        let service = NotificationService(center: center, now: { self.now })
        center.failsAdd = true
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertNotNil(service.schedulingError)
        XCTAssertEqual(task.taskReminders.count, 1)
        center.failsAdd = false
        center.dropsAdd = true
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertNotNil(service.schedulingError)
        center.dropsAdd = false
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertNil(service.schedulingError)
        XCTAssertEqual(center.pending.count, 1)
    }

    func testEditsCompletionAndDraftIdentityCancelOrphans() async throws {
        let store = try context()
        let task = task("draft", after: 60, store: store)
        let exact = TaskReminder.exact(ExactReminder(at: now.addingTimeInterval(90)))
        task.taskReminders.append(exact)
        let center = MockNotificationScheduler()
        let service = NotificationService(center: center, now: { self.now })
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        let draftIDs = Set(center.pending.keys)
        task.externalTaskID = "42"
        task.deadline = task.deadline?.addingTimeInterval(3600)
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertTrue(draftIDs.isDisjoint(with: Set(center.pending.keys)))
        let deadlineTrigger = try XCTUnwrap(center.pending[task.taskReminders[0].notificationId(for: task)]?.trigger as? UNCalendarNotificationTrigger)
        let fixed = try XCTUnwrap(center.pending[exact.notificationId(for: task)]?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(deadlineTrigger.nextTriggerDate(), now.addingTimeInterval(3660))
        XCTAssertEqual(fixed.nextTriggerDate(), now.addingTimeInterval(90))
        task.status = .done
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testAuthorizationReportsSavedRulesNeedingPermission() async throws {
        let store = try context()
        _ = task("permission", after: 60, store: store)
        let center = MockNotificationScheduler()
        let service = NotificationService(center: center, now: { self.now })
        center.status = .notDetermined
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertNotNil(service.authorizationMessage)
        center.status = .denied
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertTrue(service.authorizationMessage?.contains("Settings") == true)
        center.status = .authorized
        service.rescheduleAllReminders(modelContext: store)
        await service.waitUntilIdle()
        XCTAssertNil(service.authorizationMessage)
    }

    func testPendingRequestsFollowTheTasksChipsAndSkipPastFireTimes() async throws {
        let store = try context()
        let task = TaskItem(externalTaskID: "chips", title: "File taxes")
        task.providerWorkspaceId = "server"
        let deadline = now.addingTimeInterval(3 * 86_400)
        task.setDeadline(deadline, hasTime: true, defaults: .standard)
        store.insert(task)
        let rule = { (offset: DeadlineReminderOffset) in
            try XCTUnwrap(task.taskReminders.first { reminder in
                if case .deadline(let rule) = reminder { rule.offset == offset } else { false }
            })
        }
        let center = MockNotificationScheduler()
        let service = NotificationService(center: center, now: { self.now })

        service.rescheduleAllReminders(modelContext: store, defaultReminderMinutes: 9 * 60)
        await service.waitUntilIdle()

        // One week before already passed, so it stays saved and unscheduled.
        XCTAssertEqual(task.taskReminders.count, 4)
        XCTAssertEqual(Set(center.pending.keys), Set(try [.morningOf, .daysBefore(1), .hourBefore].map { try rule($0).notificationId(for: task) }))
        let hourBefore = try XCTUnwrap(center.pending[rule(.hourBefore).notificationId(for: task)]?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(hourBefore.nextTriggerDate(), deadline.addingTimeInterval(-3600))

        let morningOf = try rule(.morningOf)
        task.removeReminder(id: morningOf.id)
        task.addDeadlineReminder(.daysBefore(2))
        service.rescheduleAllReminders(modelContext: store, defaultReminderMinutes: 9 * 60)
        await service.waitUntilIdle()

        XCTAssertEqual(Set(center.pending.keys), Set(try [.daysBefore(1), .daysBefore(2), .hourBefore].map { try rule($0).notificationId(for: task) }))
        XCTAssertNil(center.pending[morningOf.notificationId(for: task)])
    }

    func testExactTriggerKeepsInstantAcrossTimezoneChanges() throws {
        let task = TaskItem(externalTaskID: "exact", title: "Exact")
        let instant = now.addingTimeInterval(3600)
        let reminder = TaskReminder.exact(ExactReminder(at: instant))
        let service = NotificationService(center: MockNotificationScheduler(), now: { self.now })
        let previous = NSTimeZone.default
        defer { NSTimeZone.default = previous }
        NSTimeZone.default = TimeZone(identifier: "Asia/Singapore")!
        let trigger = try XCTUnwrap(service.request(for: task, reminder: reminder, at: instant).trigger as? UNCalendarNotificationTrigger)
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(trigger.nextTriggerDate(), instant)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
    }
}
