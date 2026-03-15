import Foundation
import SwiftData

@Model
final class ProjectItem {
    @Attribute(.unique) var notionPageId: String
    var title: String
    var iconEmoji: String?
    var lastEditedTime: Date?
    var lastSyncedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.project)
    var tasks: [TaskItem] = []

    init(notionPageId: String, title: String, iconEmoji: String? = nil) {
        self.notionPageId = notionPageId
        self.title = title
        self.iconEmoji = iconEmoji
    }
}
