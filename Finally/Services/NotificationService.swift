import Foundation
import UserNotifications
import SwiftData

// MARK: - Testability abstractions

/// Minimal notification scheduling surface used by NotificationService.
/// Wrapping rather than conforming `UNUserNotificationCenter` directly avoids Sendability issues.
protocol NotificationScheduling: AnyObject {
    func addNotificationRequest(_ request: UNNotificationRequest)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

/// Production implementation — delegates straight to the system center.
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

// MARK: - NotificationService

final class NotificationService {
    static let shared = NotificationService()

    /// The scheduler used to add/remove notifications. Swap in tests.
    var center: NotificationScheduling = SystemNotificationScheduler.shared

    /// Clock — returns current time. Override in tests to control time.
    var now: () -> Date = { Date() }

    /// Production singleton init.
    init() {}

    /// Testable init — inject scheduler and clock.
    init(center: NotificationScheduling, now: @escaping () -> Date = { Date() }) {
        self.center = center
        self.now = now
    }

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

    // MARK: - Notification Body

    /// Builds a human-readable notification body from the task's due date.
    /// Uses the injected clock (`now()`) so "today" / "tomorrow" are deterministic in tests.
    func notificationBody(for task: TaskItem, using currentDate: Date) -> String {
        guard let dueDate = task.dueDate else { return "" }
        let cal = Calendar.current
        if task.dueDateHasTime {
            let timeStr = dueDate.formatted(date: .omitted, time: .shortened)
            return "Due at \(timeStr)"
        }
        if cal.isDate(dueDate, inSameDayAs: currentDate) {
            return "Due today"
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: currentDate),
           cal.isDate(dueDate, inSameDayAs: tomorrow) {
            return "Due tomorrow"
        }
        let dateStr = dueDate.formatted(date: .abbreviated, time: .omitted)
        return "Due \(dateStr)"
    }

    // MARK: - Fire Date Computation

    /// Returns the adjusted fire date for a reminder, accounting for date-only tasks.
    /// For date-only tasks, the due date is local midnight. We shift it to the user's configured
    /// preferred time (default 9 AM) before applying the interval offset, so a "30 min before"
    /// reminder fires at 8:30 AM rather than 11:30 PM the night before.
    func computeFireDate(for task: TaskItem, reminder: ReminderItem, defaultReminderMinutes: Int? = nil) -> Date? {
        // Absolute reminders bypass due-date adjustment entirely
        if let absoluteDate = reminder.absoluteDate { return absoluteDate }

        guard let dueDate = task.effectiveDate else { return nil }

        let effectiveDueDate: Date
        if task.dueDateHasTime || task.isSubtask {
            // Task has a real time component, or is a subtask whose suggestedDate already has time
            effectiveDueDate = dueDate
        } else {
            // Date-only task: shift midnight to preferred notification time
            let storedMinutes = defaultReminderMinutes
                ?? UserDefaults.standard.integer(forKey: AppConstants.defaultReminderTimeMinutesKey)
            let preferredMinutes = storedMinutes > 0 ? storedMinutes : AppConstants.defaultReminderTimeMinutes
            let hour = preferredMinutes / 60
            let minute = preferredMinutes % 60
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            effectiveDueDate = Calendar.current.date(from: comps) ?? dueDate
        }

        return effectiveDueDate.addingTimeInterval(-TimeInterval(reminder.intervalSeconds))
    }

    // MARK: - Schedule Reminder

    func scheduleReminder(for task: TaskItem, reminder: ReminderItem, defaultReminderMinutes: Int? = nil) {
        guard let fireDate = computeFireDate(for: task, reminder: reminder, defaultReminderMinutes: defaultReminderMinutes) else { return }
        guard fireDate > now() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = notificationBody(for: task, using: now())
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

        center.addNotificationRequest(request)
        reminder.isScheduled = true
    }

    // MARK: - Cancel

    func cancelRemindersForTask(_ task: TaskItem) {
        let identifiers = task.reminders.map(\.notificationId)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for reminder in task.reminders {
            reminder.isScheduled = false
        }
    }

    // MARK: - Reschedule All (Rolling Window)

    func rescheduleAllReminders(modelContext: ModelContext, defaultReminderMinutes: Int? = nil) {
        let descriptor = FetchDescriptor<ReminderItem>(
            sortBy: [SortDescriptor(\ReminderItem.intervalSeconds)]
        )
        guard let allReminders = try? modelContext.fetch(descriptor) else { return }

        // Cancel all existing
        let allIds = allReminders.map(\.notificationId)
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        // Collect reminders with valid fire dates, sorted earliest first
        let currentTime = now()
        var schedulable: [(ReminderItem, Date)] = []
        for reminder in allReminders {
            guard let task = reminder.task,
                  task.status != .done,
                  let fireDate = reminder.fireDate else {
                reminder.isScheduled = false
                continue
            }
            if fireDate > currentTime {
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
                    scheduleReminder(for: task, reminder: reminder, defaultReminderMinutes: defaultReminderMinutes)
                }
            } else {
                reminder.isScheduled = false
            }
        }
    }
}
