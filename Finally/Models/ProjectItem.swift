import Foundation
import SwiftData

@Model
final class ProjectItem {
    var externalProjectID: String
    var title: String
    var iconEmoji: String?
    var lastEditedTime: Date?
    var lastSyncedAt: Date?
    var providerWorkspaceId: String?

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.project)
    var tasks: [TaskItem] = []

    init(externalProjectID: String, title: String, iconEmoji: String? = nil) {
        self.externalProjectID = externalProjectID
        self.title = title
        self.iconEmoji = iconEmoji
    }
}
