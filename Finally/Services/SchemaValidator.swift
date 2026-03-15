import Foundation

struct ValidationResult {
    struct Issue {
        let propertyName: String
        let expectedType: String
        let message: String
    }

    var isValid: Bool { issues.isEmpty }
    var issues: [Issue] = []
    var ambiguousDueDateCandidates: [String] = []
}

final class SchemaValidator {
    private let api: NotionAPIClient

    init(api: NotionAPIClient = NotionAPIService()) {
        self.api = api
    }

    // MARK: - Validate Tasks Database

    func validateTasksDatabase(id: String) async throws -> (ValidationResult, PropertyMappings) {
        let database = try await api.retrieveDatabase(id: id)
        var result = ValidationResult()
        var mappings = PropertyMappings()

        // Required: Title property
        let titleProp = database.properties.first { $0.value.type == "title" }
        if let titleProp {
            mappings.taskTitleProperty = titleProp.key
        } else {
            result.issues.append(.init(
                propertyName: "Title",
                expectedType: "title",
                message: "Every database needs a title property. This should exist by default."
            ))
        }

        // Required: Status property
        if let explicitStatusProp = property(named: "Status", in: database.properties) {
            if explicitStatusProp.value.type == "status" {
                mappings.taskStatusProperty = explicitStatusProp.key
                mappings.taskStatusSchema = explicitStatusProp.value.status
            } else {
                result.issues.append(.init(
                    propertyName: explicitStatusProp.key,
                    expectedType: "status",
                    message: "Property '\(explicitStatusProp.key)' should be type status, found \(explicitStatusProp.value.type)."
                ))
            }
        } else if let statusProp = database.properties.first(where: { $0.value.type == "status" }) {
            mappings.taskStatusProperty = statusProp.key
            mappings.taskStatusSchema = statusProp.value.status
        } else {
            result.issues.append(.init(
                propertyName: "Status",
                expectedType: "status",
                message: "Add a Status property with options: Not Started, In Progress, Complete"
            ))
        }

        // Required: Date property for due date
        if let explicitDueProp = property(named: "Due Date", in: database.properties) {
            if explicitDueProp.value.type == "date" {
                mappings.taskDueDateProperty = explicitDueProp.key
            } else {
                result.issues.append(.init(
                    propertyName: explicitDueProp.key,
                    expectedType: "date",
                    message: "Property '\(explicitDueProp.key)' should be type date, found \(explicitDueProp.value.type)."
                ))
            }
        } else {
            let dateProps = database.properties.filter { $0.value.type == "date" }
            if dateProps.count == 1 {
                mappings.taskDueDateProperty = dateProps.first!.key
            } else if dateProps.count > 1 {
            // Multiple date properties — will need user selection
            // Default to common names
                if let match = dateProps.first(where: { $0.key.lowercased().contains("due") }) {
                    mappings.taskDueDateProperty = match.key
                } else {
                    mappings.taskDueDateProperty = dateProps.first!.key
                    result.ambiguousDueDateCandidates = dateProps.map(\.key).sorted()
                }
            } else {
                result.issues.append(.init(
                    propertyName: "Due Date",
                    expectedType: "date",
                    message: "Add a Date property named 'Due Date' for task deadlines"
                ))
            }
        }

        // Optional: Priority (select)
        if let priorityProp = database.properties.first(where: { $0.key.lowercased().contains("priority") && $0.value.type == "select" }) {
            mappings.taskPriorityProperty = priorityProp.key
        } else {
            mappings.taskPriorityProperty = nil
        }

        // Optional: Tags (multi_select)
        if let tagsProp = database.properties.first(where: { ($0.key.lowercased().contains("tag") || $0.key.lowercased().contains("label")) && $0.value.type == "multi_select" }) {
            mappings.taskTagsProperty = tagsProp.key
        } else {
            mappings.taskTagsProperty = nil
        }

        // Optional: Project (relation)
        if let projectProp = database.properties.first(where: { $0.key.lowercased().contains("project") && $0.value.type == "relation" }) {
            mappings.taskProjectProperty = projectProp.key
        } else {
            mappings.taskProjectProperty = nil
        }

        // Optional: Recurrence (select)
        if let recurrenceProp = database.properties.first(where: { ($0.key.lowercased().contains("recur") || $0.key.lowercased().contains("repeat")) && $0.value.type == "select" }) {
            mappings.taskRecurrenceProperty = recurrenceProp.key
        } else {
            mappings.taskRecurrenceProperty = nil
        }

        return (result, mappings)
    }

    // MARK: - Validate Projects Database

    func validateProjectsDatabase(id: String) async throws -> (ValidationResult, String) {
        let database = try await api.retrieveDatabase(id: id)
        var result = ValidationResult()

        let titleProp = database.properties.first { $0.value.type == "title" }
        let titleKey: String
        if let titleProp {
            titleKey = titleProp.key
        } else {
            titleKey = "Name"
            result.issues.append(.init(
                propertyName: "Title",
                expectedType: "title",
                message: "Every database needs a title property."
            ))
        }

        return (result, titleKey)
    }

    private func property(named name: String, in properties: [String: NotionPropertySchema]) -> (key: String, value: NotionPropertySchema)? {
        if let exact = properties.first(where: { $0.key == name }) {
            return exact
        }
        return properties.first(where: { $0.key.lowercased() == name.lowercased() })
    }
}
