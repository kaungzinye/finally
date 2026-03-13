import Foundation
import SwiftData

@Model
final class UserSession {
    var id: UUID = UUID()
    var workspaceId: String
    var workspaceName: String
    var tasksDatabaseId: String = ""
    var projectsDatabaseId: String = ""
    var propertyMappingsData: Data? // JSON-encoded PropertyMappings
    var lastFullSyncAt: Date?
    var createdAt: Date = Date()

    init(workspaceId: String, workspaceName: String) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
    }

    // MARK: - Property Mappings

    var propertyMappings: PropertyMappings {
        get {
            guard let data = propertyMappingsData else { return PropertyMappings() }
            return (try? JSONDecoder().decode(PropertyMappings.self, from: data)) ?? PropertyMappings()
        }
        set {
            propertyMappingsData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - PropertyMappings

struct PropertyMappings: Codable {
    /// Notion property name for task title (always the title type, auto-detected)
    var taskTitleProperty: String = "Name"
    /// Notion property name for task status
    var taskStatusProperty: String = "Status"
    /// Notion property name for due date
    var taskDueDateProperty: String = "Due Date"
    /// Notion property name for priority (optional)
    var taskPriorityProperty: String? = "Priority"
    /// Notion property name for tags (optional)
    var taskTagsProperty: String? = "Tags"
    /// Notion property name for project relation (optional)
    var taskProjectProperty: String? = "Project"
    /// Notion property name for recurrence (optional)
    var taskRecurrenceProperty: String? = "Recurrence"
    /// Notion property name for project title
    var projectTitleProperty: String = "Name"
}
