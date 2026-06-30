import Foundation

// MARK: - Reminder enums (Phase 6B)

enum ReminderAnchor: String, Codable, CaseIterable, Identifiable {
    case due = "due"
    case target = "target"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .due: return "Due date"
        case .target: return "Target date"
        }
    }
}

enum ReminderOffsetUnit: String, Codable, CaseIterable, Identifiable {
    case minutes, hours, days, weeks, months

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        case .days: return "Days"
        case .weeks: return "Weeks"
        case .months: return "Months"
        }
    }

    var bounds: ClosedRange<Int> {
        switch self {
        case .minutes: return 1...59
        case .hours: return 1...23
        case .days: return 1...30
        case .weeks: return 1...51
        case .months: return 1...11
        }
    }

    func applyOffset(value: Int, direction: ReminderOffsetDirection, to baseDate: Date, calendar: Calendar = .current) -> Date? {
        let signedValue = direction == .before ? -value : value
        switch self {
        case .minutes:
            return calendar.date(byAdding: .minute, value: signedValue, to: baseDate)
        case .hours:
            return calendar.date(byAdding: .hour, value: signedValue, to: baseDate)
        case .days:
            return calendar.date(byAdding: .day, value: signedValue, to: baseDate)
        case .weeks:
            return calendar.date(byAdding: .weekOfYear, value: signedValue, to: baseDate)
        case .months:
            return calendar.date(byAdding: .month, value: signedValue, to: baseDate)
        }
    }
}

enum ReminderOffsetDirection: String, Codable, CaseIterable, Identifiable {
    case before, after

    var id: String { rawValue }

    var label: String {
        switch self {
        case .before: return "Before"
        case .after: return "After"
        }
    }
}

// MARK: - Stored reminder entries

struct AnchoredReminder: Codable, Equatable, Identifiable {
    var id: UUID
    var anchor: ReminderAnchor
    var value: Int
    var unit: ReminderOffsetUnit
    var direction: ReminderOffsetDirection

    init(
        id: UUID = UUID(),
        anchor: ReminderAnchor,
        value: Int,
        unit: ReminderOffsetUnit,
        direction: ReminderOffsetDirection = .before
    ) {
        self.id = id
        self.anchor = anchor
        self.value = value
        self.unit = unit
        self.direction = direction
    }

    var displayLabel: String {
        let unitLabel = value == 1 ? String(unit.displayName.dropLast()) : unit.displayName
        return "\(value) \(unitLabel.lowercased()) \(direction.rawValue) \(anchor.label.lowercased())"
    }

    func isValidValue() -> Bool {
        unit.bounds.contains(value)
    }
}

struct ExplicitDateReminder: Codable, Equatable, Identifiable {
    var id: UUID
    var dateTime: Date

    init(id: UUID = UUID(), dateTime: Date) {
        self.id = id
        self.dateTime = dateTime
    }

    var displayLabel: String {
        dateTime.formatted(date: .abbreviated, time: .shortened)
    }
}

enum TaskReminder: Codable, Equatable, Identifiable {
    case anchored(AnchoredReminder)
    case explicitDate(ExplicitDateReminder)

    var id: UUID {
        switch self {
        case .anchored(let reminder): return reminder.id
        case .explicitDate(let reminder): return reminder.id
        }
    }

    var displayLabel: String {
        switch self {
        case .anchored(let reminder): return reminder.displayLabel
        case .explicitDate(let reminder): return reminder.displayLabel
        }
    }

    func isDuplicate(of other: TaskReminder) -> Bool {
        switch (self, other) {
        case (.anchored(let a), .anchored(let b)):
            return a.anchor == b.anchor && a.value == b.value && a.unit == b.unit && a.direction == b.direction
        case (.explicitDate(let a), .explicitDate(let b)):
            return abs(a.dateTime.timeIntervalSince(b.dateTime)) < 60
        default:
            return false
        }
    }

    var notificationId: String {
        "task-reminder-\(id.uuidString)"
    }

    func fireDate(for task: TaskItem, defaultReminderMinutes: Int? = nil) -> Date? {
        switch self {
        case .explicitDate(let reminder):
            return reminder.dateTime
        case .anchored(let reminder):
            guard let anchorDate = task.anchorDate(for: reminder.anchor) else { return nil }
            let base = task.adjustedAnchorDate(
                anchorDate,
                hasTime: task.hasTimeForAnchor(reminder.anchor),
                defaultReminderMinutes: defaultReminderMinutes
            )
            return reminder.unit.applyOffset(
                value: reminder.value,
                direction: reminder.direction,
                to: base
            )
        }
    }

    static func presetWeekBeforeTarget() -> TaskReminder {
        .anchored(AnchoredReminder(anchor: .target, value: 1, unit: .weeks, direction: .before))
    }

    static func presetOneDayBeforeDue() -> TaskReminder {
        .anchored(AnchoredReminder(anchor: .due, value: 1, unit: .days, direction: .before))
    }

    static func presetTwoDaysBeforeDue() -> TaskReminder {
        .anchored(AnchoredReminder(anchor: .due, value: 2, unit: .days, direction: .before))
    }

    static func presetTwoHoursBeforeDue() -> TaskReminder {
        .anchored(AnchoredReminder(anchor: .due, value: 2, unit: .hours, direction: .before))
    }

    static func presetThirtyMinutesBeforeDue() -> TaskReminder {
        .anchored(AnchoredReminder(anchor: .due, value: 30, unit: .minutes, direction: .before))
    }

    static func fromLegacy(intervalSeconds: Int, absoluteDate: Date?) -> TaskReminder? {
        if let absoluteDate {
            return .explicitDate(ExplicitDateReminder(dateTime: absoluteDate))
        }
        guard intervalSeconds >= 0 else { return nil }
        if intervalSeconds == 0 {
            return .anchored(AnchoredReminder(anchor: .due, value: 0, unit: .minutes, direction: .before))
        }
        let seconds = intervalSeconds
        if seconds % 604_800 == 0 {
            return .anchored(AnchoredReminder(anchor: .due, value: seconds / 604_800, unit: .weeks, direction: .before))
        }
        if seconds % 86_400 == 0 {
            return .anchored(AnchoredReminder(anchor: .due, value: seconds / 86_400, unit: .days, direction: .before))
        }
        if seconds % 3_600 == 0 {
            return .anchored(AnchoredReminder(anchor: .due, value: seconds / 3_600, unit: .hours, direction: .before))
        }
        if seconds % 60 == 0 {
            return .anchored(AnchoredReminder(anchor: .due, value: seconds / 60, unit: .minutes, direction: .before))
        }
        return .anchored(AnchoredReminder(anchor: .due, value: max(1, seconds / 60), unit: .minutes, direction: .before))
    }
}

enum TaskReminderCodec {
    private struct Payload: Codable {
        var anchored: [AnchoredReminder]
        var explicit: [ExplicitDateReminder]
    }

    static func decode(from json: String?) -> [TaskReminder] {
        guard let json, let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        let anchored = payload.anchored.map { TaskReminder.anchored($0) }
        let explicit = payload.explicit.map { TaskReminder.explicitDate($0) }
        return anchored + explicit
    }

    static func encode(_ reminders: [TaskReminder]) -> String? {
        var anchored: [AnchoredReminder] = []
        var explicit: [ExplicitDateReminder] = []
        for reminder in reminders {
            switch reminder {
            case .anchored(let entry): anchored.append(entry)
            case .explicitDate(let entry): explicit.append(entry)
            }
        }
        let payload = Payload(anchored: anchored, explicit: explicit)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
