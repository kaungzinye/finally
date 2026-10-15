import Foundation

struct FinallyServerReminderRule: Codable, Sendable {
    let id: String
    let kind: String
    var anchor: String?
    var value: Int?
    var unit: String?
    var direction: String?
    var at: String?

    init(_ reminder: TaskReminder) {
        id = reminder.id.uuidString
        switch reminder {
        case .anchored(let rule):
            kind = "anchored"
            anchor = Self.wireAnchor(rule.anchor)
            value = rule.value
            unit = rule.unit.rawValue
            direction = rule.direction.rawValue
        case .explicitDate(let rule):
            kind = "exact"
            at = FinallyServerTimestamp.string(from: rule.dateTime)
        }
    }

    func reminder() throws -> TaskReminder {
        guard let uuid = UUID(uuidString: id) else { throw FinallyServerClientError.invalidResponse }
        switch kind {
        case "exact":
            guard let at, let date = FinallyServerTimestamp.date(from: at) else { throw FinallyServerClientError.invalidResponse }
            return .explicitDate(ExplicitDateReminder(id: uuid, dateTime: date))
        case "anchored":
            guard let anchor, let parsedAnchor = Self.reminderAnchor(wire: anchor), let value,
                  let unit, let parsedUnit = ReminderOffsetUnit(rawValue: unit), parsedUnit.bounds.contains(value),
                  let direction, let parsedDirection = ReminderOffsetDirection(rawValue: direction) else { throw FinallyServerClientError.invalidResponse }
            return .anchored(AnchoredReminder(id: uuid, anchor: parsedAnchor, value: value, unit: parsedUnit, direction: parsedDirection))
        default: throw FinallyServerClientError.invalidResponse
        }
    }

    /// The server's reminder rule contract names the scheduled-day anchor "plannedDay".
    private static func wireAnchor(_ anchor: ReminderAnchor) -> String {
        switch anchor {
        case .deadline: "deadline"
        case .scheduledDay: "plannedDay"
        }
    }

    private static func reminderAnchor(wire: String) -> ReminderAnchor? {
        switch wire {
        case "deadline": .deadline
        case "plannedDay": .scheduledDay
        default: nil
        }
    }
}

enum FinallyServerTimestamp {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
