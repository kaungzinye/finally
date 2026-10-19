import Foundation

// MARK: - Deadline reminder offsets

/// How far ahead of a task's deadline a deadline reminder fires. Day-level offsets fire at the
/// default reminder time on their computed day. `hourBefore` needs a timed deadline.
enum DeadlineReminderOffset: Codable, Hashable, Sendable {
    case morningOf
    case daysBefore(Int)
    case weeksBefore(Int)
    case hourBefore

    /// The short list the + chip offers, in order.
    static let menu: [DeadlineReminderOffset] = [
        .morningOf, .daysBefore(1), .daysBefore(2), .daysBefore(3), .weeksBefore(1), .weeksBefore(2), .hourBefore,
    ]

    var label: String {
        switch self {
        case .morningOf: "Morning of"
        case .daysBefore(let days): days == 1 ? "1 day before" : "\(days) days before"
        case .weeksBefore(let weeks): weeks == 1 ? "1 week before" : "\(weeks) weeks before"
        case .hourBefore: "1 hour before"
        }
    }

    /// Days before run from 1 to 30 and weeks before from 1 to 12.
    var isValid: Bool {
        switch self {
        case .morningOf, .hourBefore: true
        case .daysBefore(let days): (1...30).contains(days)
        case .weeksBefore(let weeks): (1...12).contains(weeks)
        }
    }
}

// MARK: - Stored reminder rules

struct DeadlineReminder: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var offset: DeadlineReminderOffset

    init(id: UUID = UUID(), offset: DeadlineReminderOffset) {
        self.id = id
        self.offset = offset
    }
}

struct ExactReminder: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var at: Date

    init(id: UUID = UUID(), at: Date) {
        self.id = id
        self.at = at
    }

    var label: String {
        at.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

enum TaskReminder: Codable, Equatable, Identifiable, Sendable {
    case deadline(DeadlineReminder)
    case exact(ExactReminder)

    var id: UUID {
        switch self {
        case .deadline(let reminder): reminder.id
        case .exact(let reminder): reminder.id
        }
    }

    /// The reminder's chip label and icon, as task detail shows them.
    var label: String {
        switch self {
        case .deadline(let reminder): reminder.offset.label
        case .exact(let reminder): reminder.label
        }
    }

    var icon: String {
        switch self {
        case .deadline: "bell"
        case .exact: "clock"
        }
    }

    func notificationId(for task: TaskItem) -> String {
        let workspace = task.providerWorkspaceId ?? "local"
        let taskID = task.externalTaskID
        return "task-reminder-\(workspace.count):\(workspace)\(taskID.count):\(taskID):\(id.uuidString)"
    }

    /// The instant this reminder fires, or nil while it is inert. A deadline reminder is inert
    /// when it would fire after a timed deadline.
    /// Day-level offsets resolve on `calendar`'s days at `reminderMinutes` past midnight.
    func fireDate(deadline: Date?, deadlineHasTime: Bool, reminderMinutes: Int, calendar: Calendar = .current) -> Date? {
        switch self {
        case .exact(let reminder):
            return reminder.at
        case .deadline(let reminder):
            guard let deadline else { return nil }
            let fire: Date?
            switch reminder.offset {
            case .hourBefore:
                fire = deadlineHasTime ? deadline.addingTimeInterval(-3600) : nil
            case .morningOf:
                fire = Self.reminderTime(daysBefore: 0, deadline: deadline, minutes: reminderMinutes, calendar: calendar)
            case .daysBefore(let days):
                fire = Self.reminderTime(daysBefore: days, deadline: deadline, minutes: reminderMinutes, calendar: calendar)
            case .weeksBefore(let weeks):
                fire = Self.reminderTime(daysBefore: 7 * weeks, deadline: deadline, minutes: reminderMinutes, calendar: calendar)
            }
            // A deadline reminder that would fire after a timed deadline stays inert.
            guard let fire, !deadlineHasTime || fire <= deadline else { return nil }
            return fire
        }
    }

    private static func reminderTime(daysBefore days: Int, deadline: Date, minutes: Int, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: deadline)) else { return nil }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }
}

extension TaskReminder {
    /// Resolves against the task's current deadline and the default reminder time in Settings.
    func fireDate(for task: TaskItem, defaultReminderMinutes: Int? = nil) -> Date? {
        fireDate(
            deadline: task.deadline,
            deadlineHasTime: task.deadlineHasTime,
            reminderMinutes: defaultReminderMinutes ?? DefaultReminderTime.minutes()
        )
    }
}

/// The time of day, in minutes past midnight, at which day-level deadline reminders fire.
enum DefaultReminderTime {
    static func minutes(in defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: AppConstants.defaultReminderTimeMinutesKey) as? Int ?? AppConstants.defaultReminderTimeMinutes
    }
}

enum TaskReminderCodec {
    static func decode(from json: String?) -> [TaskReminder] {
        guard let json, let data = json.data(using: .utf8),
              let reminders = try? JSONDecoder().decode([TaskReminder].self, from: data) else {
            return []
        }
        return reminders
    }

    static func encode(_ reminders: [TaskReminder]) -> String? {
        guard let data = try? JSONEncoder().encode(reminders) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
