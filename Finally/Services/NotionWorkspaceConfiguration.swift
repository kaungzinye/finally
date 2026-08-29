import Foundation

struct NotionWorkspaceConfiguration: Codable {
    var tasksDatabaseID: String = ""
    var projectsDatabaseID: String = ""
    var propertyMappings = PropertyMappings()
}

extension UserSession {
    var notionConfiguration: NotionWorkspaceConfiguration {
        get {
            guard providerIdentity == .notion,
                  let providerConfigurationData,
                  let configuration = try? JSONDecoder().decode(
                      NotionWorkspaceConfiguration.self,
                      from: providerConfigurationData
                  ) else { return NotionWorkspaceConfiguration() }
            return configuration
        }
        set {
            providerConfigurationData = try? JSONEncoder().encode(newValue)
        }
    }

    var tasksDatabaseId: String {
        get { notionConfiguration.tasksDatabaseID }
        set {
            var configuration = notionConfiguration
            configuration.tasksDatabaseID = newValue
            notionConfiguration = configuration
        }
    }

    var projectsDatabaseId: String {
        get { notionConfiguration.projectsDatabaseID }
        set {
            var configuration = notionConfiguration
            configuration.projectsDatabaseID = newValue
            notionConfiguration = configuration
        }
    }

    var propertyMappings: PropertyMappings {
        get { notionConfiguration.propertyMappings }
        set {
            var configuration = notionConfiguration
            configuration.propertyMappings = newValue
            notionConfiguration = configuration
        }
    }
}

struct PropertyMappings: Codable {
    var taskTitleProperty: String = "Name"
    var taskStatusProperty: String = "Status"
    var taskStatusSchema: NotionStatusSchema?
    var taskDeadlineProperty: String = "Due Date"
    var taskPlannedDayProperty: String? = "Target"
    var taskParentProperty: String? = "Parent task"
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

extension TaskStatus {
    static func fromNotionGroup(_ group: String) -> TaskStatus? {
        switch group.lowercased() {
        case "to-do", "to do": return .notStarted
        case "in progress": return .inProgress
        case "complete", "completed", "done": return .done
        default: return nil
        }
    }

    static func fromNotionOption(_ name: String) -> TaskStatus? {
        switch name.lowercased() {
        case "not started", "not_started", "to do", "todo": return .notStarted
        case "in progress", "in_progress", "doing": return .inProgress
        case "done", "complete", "completed": return .done
        default: return nil
        }
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
        return normalized.isEmpty
            ? trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : normalized
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
        if let exactNameMatch = matchingOptions.first(where: {
            TaskStatus.fromNotionOption($0.name) == taskStatus
        }) {
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
        if !groupedOptions.isEmpty { return groupedOptions }
        return options.filter { TaskStatus.fromNotionOption($0.name) == taskStatus }
    }

    private func groupName(for notionStatus: NotionStatusValue) -> String? {
        if let optionId = notionStatus.id, let groupName = groupName(forOptionId: optionId) {
            return groupName
        }
        guard let option = options.first(where: { optionMatchesStatus($0, notionStatus: notionStatus) }) else {
            return nil
        }
        return groupName(forOptionId: option.id)
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
