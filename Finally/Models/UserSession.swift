import Foundation
import SwiftData

@Model
final class UserSession {
    var id: UUID = UUID()
    var workspaceId: String
    var workspaceName: String
    var tasksDatabaseId: String = ""
    var projectsDatabaseId: String = ""
    var propertyMappingsData: Data?
    var lastFullSyncAt: Date?
    var createdAt: Date = Date()

    init(workspaceId: String, workspaceName: String) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
    }

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

struct PropertyMappings: Codable {
    var taskTitleProperty: String = "Name"
    var taskStatusProperty: String = "Status"
    var taskStatusSchema: NotionStatusSchema?
    var taskDueDateProperty: String = "Due Date"
    var taskPriorityProperty: String? = "Priority"
    var taskTagsProperty: String? = "Tags"
    var taskProjectProperty: String? = "Project"
    var taskRecurrenceProperty: String? = "Recurrence"
    var projectTitleProperty: String = "Name"

    func taskStatus(for notionStatus: NotionStatusValue) -> TaskStatus? {
        if let mapped = taskStatusSchema?.taskStatus(for: notionStatus) {
            return mapped
        }

        return TaskStatus.fromNotionOption(notionStatus.name) ?? TaskStatus(rawValue: notionStatus.name)
    }

    func notionStatusName(for taskStatus: TaskStatus) -> String {
        taskStatusSchema?.preferredOptionName(for: taskStatus) ?? taskStatus.rawValue
    }
}

private extension String {
    var normalizedStatusToken: String {
        let normalized = lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")

        if normalized.isEmpty {
            return trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        return normalized
    }
}

extension NotionStatusSchema {
    func taskStatus(for notionStatus: NotionStatusValue) -> TaskStatus? {
        if let groupName = groupName(for: notionStatus) {
            return TaskStatus.fromNotionGroup(groupName)
        }

        return TaskStatus.fromNotionOption(notionStatus.name)
    }

    func preferredOptionName(for taskStatus: TaskStatus) -> String? {
        let matchingOptions = optionsMatching(taskStatus)
        if let exactNameMatch = matchingOptions.first(where: { TaskStatus.fromNotionOption($0.name) == taskStatus }) {
            return exactNameMatch.name
        }
        return matchingOptions.first?.name
    }

    func hasOption(for taskStatus: TaskStatus) -> Bool {
        preferredOptionName(for: taskStatus) != nil
    }

    private func optionsMatching(_ taskStatus: TaskStatus) -> [NotionSelectOption] {
        let groupedOptions = options.filter { option in
            guard let groupName = groupName(forOptionId: option.id) else { return false }
            return TaskStatus.fromNotionGroup(groupName) == taskStatus
        }

        if !groupedOptions.isEmpty {
            return groupedOptions
        }

        return options.filter { TaskStatus.fromNotionOption($0.name) == taskStatus }
    }

    private func groupName(for notionStatus: NotionStatusValue) -> String? {
        if let optionId = notionStatus.id, let groupName = groupName(forOptionId: optionId) {
            return groupName
        }

        guard let option = options.first(where: { optionMatchesStatus($0, notionStatus: notionStatus) }),
              let groupName = groupName(forOptionId: option.id) else {
            return nil
        }

        return groupName
    }

    private func optionMatchesStatus(_ option: NotionSelectOption, notionStatus: NotionStatusValue) -> Bool {
        if let notionStatusId = notionStatus.id, let optionId = option.id, notionStatusId == optionId {
            return true
        }

        return option.name.normalizedStatusToken == notionStatus.name.normalizedStatusToken
    }

    private func groupName(forOptionId optionId: String?) -> String? {
        guard let optionId, let groups else { return nil }

        return groups.first(where: { $0.optionIds?.contains(optionId) == true })?.name
    }
}
