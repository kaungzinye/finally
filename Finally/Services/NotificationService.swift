import Foundation
import UserNotifications
import SwiftData
import Observation

@MainActor
protocol NotificationScheduling: AnyObject {
    func addNotificationRequest(_ request: UNNotificationRequest) async throws
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
final class SystemNotificationScheduler: NotificationScheduling {
    static let shared = SystemNotificationScheduler()
    private init() {}

    func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

@Observable @MainActor
final class NotificationService {
    static let shared = NotificationService()
    var center: NotificationScheduling
    var now: () -> Date
    private(set) var deferredCount = 0
    private(set) var schedulingError: String?
    private(set) var authorizationMessage: String?
    private(set) var authorizationNeedsSettings = false
    @ObservationIgnored private var lastContext: ModelContext?
    @ObservationIgnored private var effectiveReminderMinutes: Int?
    @ObservationIgnored private var reconciliation: Task<Void, Never>?

    init(center: NotificationScheduling? = nil, now: @escaping () -> Date = { Date() }) {
        self.center = center ?? SystemNotificationScheduler.shared
        self.now = now
    }

    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if let lastContext { rescheduleAllReminders(modelContext: lastContext) }
        return granted
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func notificationBody(for task: TaskItem, using currentDate: Date) -> String {
        guard let deadline = task.deadline else { return "" }
        let cal = Calendar.current
        if task.deadlineHasTime { return "Deadline at \(deadline.formatted(date: .omitted, time: .shortened))" }
        if cal.isDate(deadline, inSameDayAs: currentDate) { return "Deadline today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: currentDate), cal.isDate(deadline, inSameDayAs: tomorrow) { return "Deadline tomorrow" }
        return "Deadline \(deadline.formatted(date: .abbreviated, time: .omitted))"
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = reconciliation
        reconciliation = Task {
            await previous?.value
            await operation()
        }
    }

    func waitUntilIdle() async { await reconciliation?.value }

    func cancelRemindersForTask(_ task: TaskItem, modelContext: ModelContext? = nil) {
        let workspace = task.providerWorkspaceId ?? "local"
        let taskID = task.externalTaskID
        let ruleIDs = task.taskReminders.map { $0.notificationId(for: task) }
        enqueue { [self] in
            let pending = await center.pendingNotificationRequests()
            let ids = pending.filter { $0.identifier.hasPrefix("task-reminder-") && $0.content.userInfo["workspaceId"] as? String == workspace && $0.content.userInfo["taskId"] as? String == taskID }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: Array(Set(ids + ruleIDs)))
            if let modelContext { await reconcile(modelContext: modelContext, defaultReminderMinutes: effectiveReminderMinutes) }
        }
    }

    func rescheduleAllReminders(modelContext: ModelContext, defaultReminderMinutes: Int? = nil) {
        lastContext = modelContext
        effectiveReminderMinutes = defaultReminderMinutes
        enqueue { [self] in await reconcile(modelContext: modelContext, defaultReminderMinutes: defaultReminderMinutes) }
    }

    private func reconcile(modelContext: ModelContext, defaultReminderMinutes: Int?) async {
        let tasks: [TaskItem]
        do { tasks = try modelContext.fetch(FetchDescriptor<TaskItem>()) }
        catch { schedulingError = "Saved reminders could not be read. Retry scheduling."; return }
        let current = now()
        var candidates: [(task: TaskItem, reminder: TaskReminder, date: Date, id: String)] = []
        for task in tasks where task.status != .done && !task.isDeleted && !task.serverTaskMissing {
            for reminder in task.taskReminders {
                if let date = reminder.fireDate(for: task, defaultReminderMinutes: defaultReminderMinutes), date > current {
                    candidates.append((task, reminder, date, reminder.notificationId(for: task)))
                }
            }
        }
        let status = await center.authorizationStatus()
        authorizationNeedsSettings = status == .denied || status == .provisional
        if candidates.isEmpty { authorizationMessage = nil }
        else {
            switch status {
            case .notDetermined: authorizationMessage = "Allow notifications to receive saved reminders."
            case .denied: authorizationMessage = "Reminders need notification permission in Settings."
            case .provisional: authorizationMessage = "Reminders are delivered quietly. Enable alerts in Settings."
            default: authorizationMessage = nil
            }
        }
        candidates.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let pending = await center.pendingNotificationRequests()
        let owned = pending.filter { $0.identifier.hasPrefix("task-reminder-") }
        let otherCount = pending.count - owned.count
        let budget = max(0, min(AppConstants.maxScheduledNotifications, 64 - otherCount))
        let selected = Array(candidates.prefix(budget))
        deferredCount = candidates.count - selected.count
        center.removePendingNotificationRequests(withIdentifiers: owned.map(\.identifier))
        var failed = 0
        for entry in selected {
            do { try await center.addNotificationRequest(request(for: entry.task, reminder: entry.reminder, at: entry.date)) }
            catch { failed += 1 }
        }
        let accepted = Set(await center.pendingNotificationRequests().map(\.identifier))
        let missing = selected.filter { !accepted.contains($0.id) }.count
        schedulingError = max(failed, missing) > 0 ? "\(max(failed, missing)) reminders could not be scheduled. Their rules stay saved. Retry scheduling." : nil
    }

    func request(for task: TaskItem, reminder: TaskReminder, at fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = notificationBody(for: task, using: now())
        content.sound = .default
        content.userInfo = ["taskId": task.externalTaskID, "workspaceId": task.providerWorkspaceId ?? "local"]
        var calendar = Calendar(identifier: .gregorian)
        // Resolved reminders represent instants. UTC components preserve them across timezone changes.
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: reminder.notificationId(for: task), content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
}
