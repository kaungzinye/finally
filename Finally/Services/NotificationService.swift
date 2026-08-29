import Foundation
import UserNotifications
import SwiftData

protocol NotificationScheduling: AnyObject {
    func addNotificationRequest(_ request: UNNotificationRequest)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

final class SystemNotificationScheduler: NotificationScheduling {
    static let shared = SystemNotificationScheduler()
    private init() {}

    func addNotificationRequest(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

struct ScheduledReminderRef: Identifiable {
    let id: UUID
    let task: TaskItem
    let reminder: TaskReminder
    let fireDate: Date
    let notificationId: String
}

final class NotificationService {
    static let shared = NotificationService()

    var center: NotificationScheduling = SystemNotificationScheduler.shared
    var now: () -> Date = { Date() }

    init() {}

    init(center: NotificationScheduling, now: @escaping () -> Date = { Date() }) {
        self.center = center
        self.now = now
    }

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func notificationBody(for task: TaskItem, using currentDate: Date) -> String {
        guard let deadline = task.deadline else { return "" }
        let cal = Calendar.current
        if task.deadlineHasTime {
            let timeStr = deadline.formatted(date: .omitted, time: .shortened)
            return "Deadline at \(timeStr)"
        }
        if cal.isDate(deadline, inSameDayAs: currentDate) {
            return "Deadline today"
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: currentDate),
           cal.isDate(deadline, inSameDayAs: tomorrow) {
            return "Deadline tomorrow"
        }
        let dateStr = deadline.formatted(date: .abbreviated, time: .omitted)
        return "Deadline \(dateStr)"
    }

    func scheduleReminder(for task: TaskItem, reminder: TaskReminder, defaultReminderMinutes: Int? = nil) {
        guard let fireDate = reminder.fireDate(for: task, defaultReminderMinutes: defaultReminderMinutes) else { return }
        guard fireDate > now() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = notificationBody(for: task, using: now())
        content.sound = .default
        content.userInfo = ["taskId": task.externalTaskID]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: reminder.notificationId,
            content: content,
            trigger: trigger
        )

        center.addNotificationRequest(request)
    }

    func cancelRemindersForTask(_ task: TaskItem) {
        let identifiers = task.taskReminders.map(\.notificationId)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func rescheduleAllReminders(modelContext: ModelContext, defaultReminderMinutes: Int? = nil) {
        guard let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) else { return }

        var allIds: [String] = []
        for task in tasks {
            allIds.append(contentsOf: task.taskReminders.map(\.notificationId))
        }
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        let currentTime = now()
        var schedulable: [ScheduledReminderRef] = []

        for task in tasks where task.status != .done {
            for reminder in task.taskReminders {
                guard let fireDate = reminder.fireDate(for: task, defaultReminderMinutes: defaultReminderMinutes),
                      fireDate > currentTime else { continue }
                schedulable.append(
                    ScheduledReminderRef(
                        id: reminder.id,
                        task: task,
                        reminder: reminder,
                        fireDate: fireDate,
                        notificationId: reminder.notificationId
                    )
                )
            }
        }

        schedulable.sort { $0.fireDate < $1.fireDate }

        let limit = min(schedulable.count, AppConstants.maxScheduledNotifications)
        for i in 0..<limit {
            let entry = schedulable[i]
            scheduleReminder(for: entry.task, reminder: entry.reminder, defaultReminderMinutes: defaultReminderMinutes)
        }
    }
}
