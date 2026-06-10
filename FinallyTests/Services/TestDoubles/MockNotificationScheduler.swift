import UserNotifications
@testable import Finally

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
