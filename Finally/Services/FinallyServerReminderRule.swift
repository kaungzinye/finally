import Foundation

/// One reminder rule in the shape `docs/contracts/task-reminders.md` pins.
struct FinallyServerReminderRule: Codable, Sendable {
    let id: String
    let kind: String
    var offset: String?
    var value: Int?
    var at: String?

    init(_ reminder: TaskReminder) {
        id = reminder.id.uuidString
        switch reminder {
        case .deadline(let rule):
            kind = "deadline"
            switch rule.offset {
            case .morningOf: offset = "morningOf"
            case .daysBefore(let days): offset = "daysBefore"; value = days
            case .weeksBefore(let weeks): offset = "weeksBefore"; value = weeks
            case .hourBefore: offset = "hourBefore"
            }
        case .exact(let rule):
            kind = "exact"
            at = FinallyServerTimestamp.string(from: rule.at)
        }
    }

    func reminder() throws -> TaskReminder {
        guard let uuid = UUID(uuidString: id) else { throw FinallyServerClientError.invalidResponse }
        switch kind {
        case "exact":
            guard let at, let date = FinallyServerTimestamp.date(from: at) else { throw FinallyServerClientError.invalidResponse }
            return .exact(ExactReminder(id: uuid, at: date))
        case "deadline":
            guard at == nil, let offset = deadlineOffset() else { throw FinallyServerClientError.invalidResponse }
            return .deadline(DeadlineReminder(id: uuid, offset: offset))
        default:
            throw FinallyServerClientError.invalidResponse
        }
    }

    private func deadlineOffset() -> DeadlineReminderOffset? {
        let decoded: DeadlineReminderOffset? = switch (offset, value) {
        case ("morningOf", nil): .morningOf
        case ("hourBefore", nil): .hourBefore
        case ("daysBefore", let days?): .daysBefore(days)
        case ("weeksBefore", let weeks?): .weeksBefore(weeks)
        default: nil
        }
        return decoded.flatMap { $0.isValid ? $0 : nil }
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
