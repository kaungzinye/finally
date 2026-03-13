import Foundation
import UserNotifications
import SwiftData

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - Permission

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

    // MARK: - Schedule Reminder

    func scheduleReminder(for task: TaskItem, reminder: ReminderItem) {
        guard let dueDate = task.dueDate else { return }

        let fireDate = dueDate.addingTimeInterval(-Double(reminder.intervalSeconds))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = reminder.label
        content.sound = .default
        content.userInfo = ["taskId": task.notionPageId]

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

        UNUserNotificationCenter.current().add(request)
        reminder.isScheduled = true
    }

    // MARK: - Cancel

    func cancelRemindersForTask(_ task: TaskItem) {
        let identifiers = task.reminders.map(\.notificationId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        for reminder in task.reminders {
            reminder.isScheduled = false
        }
    }

    // MARK: - Reschedule All (Rolling Window)

    func rescheduleAllReminders(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ReminderItem>(
            sortBy: [SortDescriptor(\ReminderItem.intervalSeconds)]
        )
        guard let allReminders = try? modelContext.fetch(descriptor) else { return }

        // Cancel all existing
        let allIds = allReminders.map(\.notificationId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allIds)

        // Collect reminders with valid fire dates, sorted earliest first
        var schedulable: [(ReminderItem, Date)] = []
        for reminder in allReminders {
            guard let task = reminder.task,
                  let dueDate = task.dueDate,
                  task.status != .done else {
                reminder.isScheduled = false
                continue
            }
            let fireDate = dueDate.addingTimeInterval(-Double(reminder.intervalSeconds))
            if fireDate > Date() {
                schedulable.append((reminder, fireDate))
            } else {
                reminder.isScheduled = false
            }
        }

        schedulable.sort { $0.1 < $1.1 }

        // Schedule up to the limit
        let limit = min(schedulable.count, AppConstants.maxScheduledNotifications)
        for i in 0..<schedulable.count {
            let (reminder, _) = schedulable[i]
            if i < limit {
                if let task = reminder.task {
                    scheduleReminder(for: task, reminder: reminder)
                }
            } else {
                reminder.isScheduled = false
            }
        }
    }
}
