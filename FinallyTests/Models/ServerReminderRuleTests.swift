import Foundation
import SwiftData
import UserNotifications
import XCTest
@testable import Finally

final class ServerReminderRuleTests: XCTestCase {
    private let ruleID = UUID(uuidString: "5B0A3C1E-7D44-4F1B-9E0C-2A6D8B3F1C47")!

    private func wireObject(_ reminder: TaskReminder) throws -> NSDictionary {
        let data = try JSONEncoder().encode(FinallyServerReminderRule(reminder))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func decode(_ json: String) throws -> TaskReminder {
        try JSONDecoder().decode(FinallyServerReminderRule.self, from: Data(json.utf8)).reminder()
    }

    func testDeadlineRulesEncodeTheContractShapes() throws {
        let id = ruleID.uuidString
        XCTAssertEqual(try wireObject(.deadline(DeadlineReminder(id: ruleID, offset: .morningOf))),
                       ["id": id, "kind": "deadline", "offset": "morningOf"])
        XCTAssertEqual(try wireObject(.deadline(DeadlineReminder(id: ruleID, offset: .daysBefore(1)))),
                       ["id": id, "kind": "deadline", "offset": "daysBefore", "value": 1])
        XCTAssertEqual(try wireObject(.deadline(DeadlineReminder(id: ruleID, offset: .weeksBefore(1)))),
                       ["id": id, "kind": "deadline", "offset": "weeksBefore", "value": 1])
        XCTAssertEqual(try wireObject(.deadline(DeadlineReminder(id: ruleID, offset: .hourBefore))),
                       ["id": id, "kind": "deadline", "offset": "hourBefore"])
    }

    func testExactRuleEncodesTheContractShape() throws {
        let instant = try XCTUnwrap(FinallyServerTimestamp.date(from: "2026-10-20T15:00:00.000Z"))

        XCTAssertEqual(try wireObject(.exact(ExactReminder(id: ruleID, at: instant))),
                       ["id": ruleID.uuidString, "kind": "exact", "at": "2026-10-20T15:00:00.000Z"])
    }

    func testDeadlineRulesDecodeTheContractShapes() throws {
        let id = ruleID.uuidString
        XCTAssertEqual(try decode(#"{"id":"\#(id)","kind":"deadline","offset":"morningOf"}"#),
                       .deadline(DeadlineReminder(id: ruleID, offset: .morningOf)))
        XCTAssertEqual(try decode(#"{"id":"\#(id)","kind":"deadline","offset":"daysBefore","value":30}"#),
                       .deadline(DeadlineReminder(id: ruleID, offset: .daysBefore(30))))
        XCTAssertEqual(try decode(#"{"id":"\#(id)","kind":"deadline","offset":"weeksBefore","value":12}"#),
                       .deadline(DeadlineReminder(id: ruleID, offset: .weeksBefore(12))))
        XCTAssertEqual(try decode(#"{"id":"\#(id.lowercased())","kind":"deadline","offset":"hourBefore"}"#),
                       .deadline(DeadlineReminder(id: ruleID, offset: .hourBefore)))
    }

    func testRulesOutsideTheContractAreRejected() {
        let id = ruleID.uuidString
        let rejected = [
            #"{"id":"\#(id)","kind":"anchored","offset":"morningOf"}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"monthsBefore","value":1}"#,
            #"{"id":"\#(id)","kind":"deadline"}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"daysBefore"}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"daysBefore","value":0}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"daysBefore","value":31}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"weeksBefore","value":0}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"weeksBefore","value":13}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"morningOf","value":1}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"hourBefore","value":1}"#,
            #"{"id":"\#(id)","kind":"deadline","offset":"morningOf","at":"2026-10-20T15:00:00.000Z"}"#,
            #"{"id":"\#(id)","kind":"exact"}"#,
            #"{"id":"\#(id)","kind":"exact","at":"tomorrow"}"#,
            #"{"id":"not-a-uuid","kind":"deadline","offset":"morningOf"}"#,
        ]
        for json in rejected {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    @MainActor
    func testPersistedServerRuleSchedulesThroughFreshContextAndService() async throws {
        let container = try ModelContainer(for: TaskItem.self, ProjectItem.self, UserSession.self,
                                           DailyFocus.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let originalContext = ModelContext(container)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let instant = now.addingTimeInterval(600)
        let rule = TaskReminder.exact(ExactReminder(at: instant))
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
        let original = TaskReminder.exact(ExactReminder(id: id, at: instant))
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

    func testSharedRuleUUIDKeepsProviderWorkspaceAndTaskNotificationsDistinct() {
        let reminder = TaskReminder.deadline(DeadlineReminder(offset: .hourBefore))
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
