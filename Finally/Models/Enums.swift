import SwiftUI

// MARK: - TaskStatus

enum TaskStatus: String, Codable, CaseIterable {
    case notStarted = "Not started"
    case inProgress = "In progress"
    case done = "Done"

    /// Map from Notion status group name to TaskStatus
    static func fromNotionGroup(_ group: String) -> TaskStatus? {
        switch group.lowercased() {
        case "to-do", "to do": return .notStarted
        case "in progress": return .inProgress
        case "complete", "completed", "done": return .done
        default: return nil
        }
    }

    /// Map from Notion status option name to TaskStatus
    static func fromNotionOption(_ name: String) -> TaskStatus? {
        switch name.lowercased() {
        case "not started", "not_started", "to do", "todo": return .notStarted
        case "in progress", "in_progress", "doing": return .inProgress
        case "done", "complete", "completed": return .done
        default: return nil
        }
    }
}

// MARK: - TaskPriority

enum TaskPriority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: Color {
        switch self {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .urgent: return "flag.fill"
        case .high: return "flag.fill"
        case .medium: return "flag.fill"
        case .low: return "flag"
        }
    }

    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

// MARK: - Recurrence

enum Recurrence: String, Codable, CaseIterable {
    case none = "None"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"

    var icon: String {
        switch self {
        case .none: return "arrow.counterclockwise"
        case .daily: return "repeat"
        case .weekly: return "repeat"
        case .monthly: return "repeat"
        case .yearly: return "repeat"
        }
    }

    /// Compute the next due date from the given date.
    /// If the result is still in the past, keep advancing until it's in the future.
    func nextDueDate(from date: Date) -> Date? {
        guard self != .none else { return nil }

        let calendar = Calendar.current
        var next = date

        let component: Calendar.Component
        let value: Int

        switch self {
        case .none: return nil
        case .daily: component = .day; value = 1
        case .weekly: component = .day; value = 7
        case .monthly: component = .month; value = 1
        case .yearly: component = .year; value = 1
        }

        repeat {
            guard let advanced = calendar.date(byAdding: component, value: value, to: next) else {
                return nil
            }
            next = advanced
        } while next <= Date()

        return next
    }
}
