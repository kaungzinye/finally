import Foundation
import SwiftData
import UserNotifications
import XCTest
@testable import Finally

final class ServerReminderRuleTests: XCTestCase {
    @MainActor
    func testPersistedServerRuleSchedulesThroughFreshContextAndService() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self,
                                           DailyFocus.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let originalContext = ModelContext(container)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let instant = now.addingTimeInterval(600)
        let rule = TaskReminder.explicitDate(ExplicitDateReminder(dateTime: instant))
        let wire = try JSONEncoder().encode(FinallyServerReminderRule(rule))
        let task = TaskItem(externalTaskID: "1", title: "Proposal")
        task.providerWorkspaceId = "server"
        task.taskReminders = [try JSONDecoder().decode(FinallyServerReminderRule.self, from: wire).reminder()]
        originalContext.insert(task)
        try originalContext.save()

        let freshContext = ModelContext(container)
        let persisted = try XCTUnwrap(freshContext.fetch(FetchDescriptor<TaskItem>()).first)
        let scheduler = MockNotificationScheduler()
        let service = NotificationService(center: scheduler, now: { now })
        service.rescheduleAllReminders(modelContext: freshContext)
        await service.waitUntilIdle()

        XCTAssertEqual(persisted.taskReminders, [rule])
        let request = try XCTUnwrap(scheduler.pending[rule.notificationId(for: persisted)])
        XCTAssertEqual((request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(), instant)
        XCTAssertEqual(request.content.userInfo["workspaceId"] as? String, "server")
    }

    func testExactReminderPreservesIdentityAndFixedInstantThroughWireRoundTrip() throws {
        let id = UUID()
        let instant = Date(timeIntervalSince1970: 2_000_000_000.125)
        let original = TaskReminder.explicitDate(ExplicitDateReminder(id: id, dateTime: instant))
        let data = try JSONEncoder().encode(FinallyServerReminderRule(original))
        let wire = try JSONDecoder().decode(FinallyServerReminderRule.self, from: data)
        let decoded = try wire.reminder()
        let task = TaskItem(externalTaskID: "1", title: "Proposal")
        task.deadline = instant.addingTimeInterval(3600)

        XCTAssertEqual(wire.kind, "exact")
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(try XCTUnwrap(decoded.fireDate(for: task)).timeIntervalSince1970,
                       instant.timeIntervalSince1970, accuracy: 0.001)
        task.deadline = instant.addingTimeInterval(7200)
        XCTAssertEqual(try XCTUnwrap(decoded.fireDate(for: task)).timeIntervalSince1970,
                       instant.timeIntervalSince1970, accuracy: 0.001)
    }

    func testExactReminderReadsRFC3339FractionsAndTimezoneOffsets() throws {
        let id = UUID()
        let payload = """
        {"id":"\(id.uuidString)","kind":"exact","at":"2026-10-20T17:30:00.125+08:00"}
        """
        let wire = try JSONDecoder().decode(FinallyServerReminderRule.self, from: Data(payload.utf8))
        let reminder = try wire.reminder()
        let task = TaskItem(externalTaskID: "1", title: "Proposal")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let expected = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 20,
                                                                 hour: 9, minute: 30)))
            .addingTimeInterval(0.125)

        XCTAssertEqual(reminder.id, id)
        XCTAssertEqual(try XCTUnwrap(reminder.fireDate(for: task)).timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testAnchoredReminderRetainsRuleAndMovesWithAcceptedDeadline() throws {
        let id = UUID()
        let original = TaskReminder.anchored(AnchoredReminder(id: id, anchor: .deadline,
                                                             value: 30, unit: .minutes, direction: .before))
        let data = try JSONEncoder().encode(FinallyServerReminderRule(original))
        let wire = try JSONDecoder().decode(FinallyServerReminderRule.self, from: data)
        let decoded = try wire.reminder()
        let task = TaskItem(externalTaskID: "1", title: "Proposal")
        task.deadlineHasTime = true
        let acceptedDeadline = Date(timeIntervalSince1970: 2_000_000_000)
        task.deadline = acceptedDeadline

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.fireDate(for: task), acceptedDeadline.addingTimeInterval(-1800))
        task.deadline = acceptedDeadline.addingTimeInterval(3600)
        XCTAssertEqual(decoded.fireDate(for: task), acceptedDeadline.addingTimeInterval(1800))
    }

    func testSharedRuleUUIDKeepsProviderWorkspaceAndTaskNotificationsDistinct() {
        let reminder = TaskReminder.anchored(AnchoredReminder(anchor: .deadline, value: 30, unit: .minutes))
        let first = TaskItem(externalTaskID: "1", title: "Proposal")
        first.providerWorkspaceId = "server"
        let second = TaskItem(externalTaskID: "2", title: "Review")
        second.providerWorkspaceId = "server"
        let otherWorkspace = TaskItem(externalTaskID: "1", title: "Proposal")
        otherWorkspace.providerWorkspaceId = "notion"

        let firstIdentifier = reminder.notificationId(for: first)
        first.title = "Edited proposal"
        XCTAssertEqual(reminder.notificationId(for: first), firstIdentifier)
        XCTAssertEqual(Set([reminder.notificationId(for: first), reminder.notificationId(for: second),
                            reminder.notificationId(for: otherWorkspace)]).count, 3)
    }
}
