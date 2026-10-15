import SwiftUI

// The app and the widget both compile this file.

// MARK: - TaskStatus

enum TaskStatus: String, Codable, CaseIterable {
    case notStarted = "Not started"
    case inProgress = "In progress"
    case done = "Complete"
}

// MARK: - TaskPriority

enum TaskPriority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: Color { Palette.priority(named: rawValue) }

    var icon: String {
        switch self {
        case .urgent: return "flag.fill"
        case .high: return "flag.fill"
        case .medium: return "flag.fill"
        case .low: return "flag.fill"
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
