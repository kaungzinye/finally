import UserNotifications
@testable import Finally

@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []
    var pending: [String: UNNotificationRequest] = [:]
    var status: UNAuthorizationStatus = .authorized
    var failsAdd = false
    var dropsAdd = false

    func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        if failsAdd { throw NSError(domain: "Scheduling", code: 1) }
        addedRequests.append(request)
        if !dropsAdd { pending[request.identifier] = request }
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func pendingNotificationRequests() async -> [UNNotificationRequest] { Array(pending.values) }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        identifiers.forEach { pending.removeValue(forKey: $0) }
    }

    func reset() {
        addedRequests = []
        removedIdentifiers = []
        pending = [:]
    }
}
