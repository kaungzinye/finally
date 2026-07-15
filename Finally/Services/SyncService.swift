import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

enum TaskSyncError: Error, LocalizedError {
    case permissionDenied
    case authenticationExpired
    case rateLimited
    case remoteTaskUnavailable
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "You don't have edit access to this database"
        case .authenticationExpired:
            return "Your task provider connection has expired. Reconnect it in Settings."
        case .rateLimited:
            return "Sync is temporarily rate-limited. Try again in a moment."
        case .remoteTaskUnavailable:
            return "This task is no longer available from its provider. Refresh and try again."
        case .serviceUnavailable:
            return "Sync is temporarily unavailable. Try again."
        }
    }
}

@Observable
final class SyncService {
    private let api: NotionAPIClient
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let shortDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    var isSyncing = false
    var lastError: String?

    init(api: NotionAPIClient = NotionAPIService()) {
        self.api = api
    }

    // MARK: - Sync On Launch

    func syncOnLaunch(modelContext: ModelContext) async {
        guard let session = fetchSession(modelContext: modelContext) else {
            print("[Sync] No session found, skipping sync")
            return
        }

        print("[Sync] Starting sync. tasksDb=\(session.tasksDatabaseId), projectsDb=\(session.projectsDatabaseId), lastFullSync=\(String(describing: session.lastFullSyncAt))")
        isSyncing = true
        lastError = nil

        do {
            // Also force full sync if no tasks exist locally
            let taskCount = (try? modelContext.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
            let shouldFullSync = taskCount == 0 || session.lastFullSyncAt == nil ||
                (session.lastFullSyncAt?.timeIntervalSinceNow ?? 0) < -Double(AppConstants.fullSyncIntervalHours * 3600)

            if shouldFullSync {
                print("[Sync] Running full sync")
                try await fullSync(session: session, modelContext: modelContext)
                print("[Sync] Full sync complete")
            } else {
                print("[Sync] Running incremental sync")
                try await incrementalSync(session: session, modelContext: modelContext)
                print("[Sync] Incremental sync complete")
            }
        } catch {
            print("[Sync] Error: \(error)")
            lastError = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Incremental Sync

    func incrementalSync(session: UserSession, modelContext: ModelContext) async throws {
        let lastSync = session.lastFullSyncAt ?? Date.distantPast
        let isoDate = dateFormatter.string(from: lastSync)

        let filter: [String: Any] = [
            "timestamp": "last_edited_time",
            "last_edited_time": ["after": isoDate]
        ]

        var mappings = session.propertyMappings
        mappings = try await refreshTaskStatusSchemaIfNeeded(
            session: session,
            currentMappings: mappings,
            forceRefresh: !session.tasksDatabaseId.isEmpty
        )

        if !session.projectsDatabaseId.isEmpty {
            let projectPages = try await api.queryAllPages(databaseId: session.projectsDatabaseId, filter: filter, sorts: nil)
            print("[Sync] Incremental: fetched \(projectPages.count) updated projects")
            upsertProjects(projectPages, mappings: mappings, modelContext: modelContext)
        }

        if !session.tasksDatabaseId.isEmpty {
            let taskPages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: filter, sorts: nil)
            print("[Sync] Incremental: fetched \(taskPages.count) updated tasks")
            upsertTasks(taskPages, mappings: mappings, modelContext: modelContext)
        }

        session.lastFullSyncAt = Date()
        try modelContext.save()
    }

    // MARK: - Full Sync

    func fullSync(session: UserSession, modelContext: ModelContext) async throws {
        var mappings = session.propertyMappings
        mappings = try await refreshTaskStatusSchemaIfNeeded(
            session: session,
            currentMappings: mappings,
            forceRefresh: !session.tasksDatabaseId.isEmpty
        )

        if !session.projectsDatabaseId.isEmpty {
            print("[Sync] Fetching projects from DB: \(session.projectsDatabaseId)")
            let allProjectPages = try await api.queryAllPages(databaseId: session.projectsDatabaseId, filter: nil, sorts: nil)
            print("[Sync] Fetched \(allProjectPages.count) project pages from Notion")
            let remoteProjectIds = Set(allProjectPages.map(\.id))

            upsertProjects(allProjectPages, mappings: mappings, modelContext: modelContext)
            deleteStaleItems(ProjectItem.self, remoteIds: remoteProjectIds, modelContext: modelContext)
        } else {
            print("[Sync] No projects DB configured, skipping")
        }

        if !session.tasksDatabaseId.isEmpty {
            print("[Sync] Fetching tasks from DB: \(session.tasksDatabaseId)")
            let allTaskPages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: nil, sorts: nil)
            print("[Sync] Fetched \(allTaskPages.count) task pages from Notion")
            let remoteTaskIds = Set(allTaskPages.map(\.id))

            upsertTasks(allTaskPages, mappings: mappings, modelContext: modelContext)
            deleteStaleItems(TaskItem.self, remoteIds: remoteTaskIds, modelContext: modelContext)

            let localCount = (try? modelContext.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
            print("[Sync] Local task count after upsert: \(localCount)")
        } else {
            print("[Sync] No tasks DB configured, skipping")
        }

        session.lastFullSyncAt = Date()
        try modelContext.save()
        print("[Sync] Full sync saved successfully")
    }

    // MARK: - Push Dirty Changes

    func pushDirtyChanges(session: UserSession, modelContext: ModelContext) async throws {
        do {
            try await pushDirtyChangesUsingProvider(session: session, modelContext: modelContext)
        } catch let error as NotionAPIError {
            throw taskSyncError(for: error)
        }
    }

    private func pushDirtyChangesUsingProvider(session: UserSession, modelContext: ModelContext) async throws {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDirty == true && $0.isLocalOnly == false })
        let dirtyTasks = try modelContext.fetch(descriptor)  // Bug 2 fix: propagate fetch errors instead of silently returning []

        var mappings = session.propertyMappings
        mappings = try await refreshTaskStatusSchemaIfNeeded(
            for: dirtyTasks,
            session: session,
            currentMappings: mappings,
            forceRefresh: false
        )

        for task in dirtyTasks {
            do {
                try await push(task, session: session, mappings: mappings, modelContext: modelContext)
            } catch NotionAPIError.rateLimited(let retryAfter) {
                try? await Task.sleep(for: .seconds(retryAfter))
                do {
                    try await push(task, session: session, mappings: mappings, modelContext: modelContext)
                } catch let retryError as NotionAPIError {
                    throw retryError
                } catch {
                    print("[Sync] Failed to push task '\(task.title)' after rate-limit retry: \(error)")
                }
            } catch let error as NotionAPIError {
                throw error
            } catch {
                // Bug 3 fix: log and continue — don't clear isDirty so it retries next cycle
                print("[Sync] Failed to push task '\(task.title)': \(error)")
            }
        }

        reloadWidgetTimelines()
    }

    private func push(
        _ task: TaskItem,
        session: UserSession,
        mappings: PropertyMappings,
        modelContext: ModelContext
    ) async throws {
        let properties = buildNotionProperties(for: task, mappings: mappings)
        if task.lastSyncedAt == nil, !session.tasksDatabaseId.isEmpty {
            let created = try await api.createPage(databaseId: session.tasksDatabaseId, properties: properties)
            task.notionPageId = created.id
        } else if task.lastSyncedAt == nil {
            return
        } else {
            _ = try await api.updatePage(pageId: task.notionPageId, properties: properties)
        }
        task.isDirty = false
        task.lastSyncedAt = Date()
        try modelContext.save()
    }

    private func taskSyncError(for error: NotionAPIError) -> TaskSyncError {
        switch error {
        case .permissionDenied:
            return .permissionDenied
        case .unauthorized:
            return .authenticationExpired
        case .rateLimited:
            return .rateLimited
        case .notFound:
            return .remoteTaskUnavailable
        case .badRequest, .serverError, .networkError, .decodingError:
            return .serviceUnavailable
        }
    }

    // MARK: - Upsert Projects

    private func upsertProjects(_ pages: [NotionPage], mappings: PropertyMappings, modelContext: ModelContext) {
        for page in pages {
            let title = extractTitle(from: page, propertyName: mappings.projectTitleProperty)
            let editedTime = parseDate(page.lastEditedTime)
            let emoji = page.icon?.emoji

            let pageId = page.id
            let descriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate<ProjectItem> { item in
                item.notionPageId == pageId
            })

            if let existing = (try? modelContext.fetch(descriptor))?.first {
                existing.title = title
                existing.iconEmoji = emoji
                existing.lastEditedTime = editedTime
                existing.lastSyncedAt = Date()
            } else {
                let project = ProjectItem(notionPageId: page.id, title: title, iconEmoji: emoji)
                project.lastEditedTime = editedTime
                project.lastSyncedAt = Date()
                modelContext.insert(project)
            }
        }
    }

    // MARK: - Upsert Tasks

    private func upsertTasks(_ pages: [NotionPage], mappings: PropertyMappings, modelContext: ModelContext) {
        for page in pages {
            let title = extractTitle(from: page, propertyName: mappings.taskTitleProperty)
            let editedTime = parseDate(page.lastEditedTime)

            let pageId = page.id
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { item in
                item.notionPageId == pageId
            })

            let task: TaskItem
            if let existing = (try? modelContext.fetch(descriptor))?.first {
                // Don't overwrite local dirty changes
                guard !existing.isDirty else {
                    print("[Sync] Skipping upsert for dirty task '\(existing.title)' (id: \(pageId))")
                    continue
                }
                task = existing
            } else {
                task = TaskItem(notionPageId: page.id, title: title)
                modelContext.insert(task)
            }

            task.title = title
            task.lastEditedTime = editedTime
            task.lastSyncedAt = Date()

            // Status
            if let statusProp = page.properties[mappings.taskStatusProperty],
               let notionStatus = statusProp.status {
                let mapped = mappings.taskStatus(for: notionStatus) ?? .notStarted
                print("[Sync] Task '\(title)' status: '\(notionStatus.name)' → \(mapped.rawValue)")
                task.status = mapped
            } else {
                print("[Sync] Task '\(title)' NO STATUS FOUND. Property key: '\(mappings.taskStatusProperty)', available keys: \(Array(page.properties.keys))")
            }

            // Due Date — official deadline only
            if let dateProp = page.properties[mappings.taskDueDateProperty],
               let dateStr = dateProp.date?.start {
                if let endStr = dateProp.date?.end {
                    task.targetDate = parseDate(dateStr)
                    task.targetDateHasTime = dateStr.contains("T")
                    task.dueDate = parseDate(endStr)
                    task.dueDateHasTime = endStr.contains("T")
                } else {
                    task.dueDate = parseDate(dateStr)
                    task.dueDateHasTime = dateStr.contains("T")
                }
            } else {
                task.dueDate = nil
                task.dueDateHasTime = false
            }

            // Target Date — optional secondary planning date
            if let targetKey = mappings.taskTargetDateProperty,
               let targetProp = page.properties[targetKey],
               let targetStr = targetProp.date?.start {
                task.targetDate = parseDate(targetStr)
                task.targetDateHasTime = targetStr.contains("T")
            }

            task.validateTargetDate()
            task.startDate = nil

            // Priority
            if let priorityKey = mappings.taskPriorityProperty,
               let priorityProp = page.properties[priorityKey],
               let priorityName = priorityProp.select?.name {
                task.priority = TaskPriority(rawValue: priorityName)
            }

            // Tags (with colors)
            if let tagsKey = mappings.taskTagsProperty,
               let tagsProp = page.properties[tagsKey],
               let multiSelect = tagsProp.multiSelect {
                task.tags = multiSelect.map(\.name)
                task.tagColors = multiSelect.map { $0.color ?? "default" }
            }

            // Recurrence
            if let recurrenceKey = mappings.taskRecurrenceProperty,
               let recurrenceProp = page.properties[recurrenceKey],
               let recurrenceName = recurrenceProp.select?.name {
                task.recurrence = Recurrence(rawValue: recurrenceName) ?? .none
            }

            // Project Relation
            if let projectKey = mappings.taskProjectProperty,
               let projectProp = page.properties[projectKey],
               let relations = projectProp.relation,
               let firstRelation = relations.first {
                let relationId = firstRelation.id
                let projectDescriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate<ProjectItem> { item in
                    item.notionPageId == relationId
                })
                task.project = (try? modelContext.fetch(projectDescriptor))?.first
            } else {
                task.project = nil
            }

            // Parent relation (subtasks)
            if let parentKey = mappings.taskParentProperty,
               let parentProp = page.properties[parentKey],
               let relations = parentProp.relation,
               let firstRelation = relations.first {
                let parentId = firstRelation.id
                task.parentId = parentId
                let parentDescriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { item in
                    item.notionPageId == parentId
                })
                task.parent = (try? modelContext.fetch(parentDescriptor))?.first
                task.isLocalOnly = false
            } else if task.parentId == nil {
                task.parent = nil
            }
        }

        linkPendingSubtaskParents(modelContext: modelContext)
    }

    private func linkPendingSubtaskParents(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.parentId != nil })
        guard let tasks = try? modelContext.fetch(descriptor) else { return }

        for task in tasks {
            guard let parentId = task.parentId else { continue }
            let parentDescriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { item in
                item.notionPageId == parentId
            })
            if let parent = try? modelContext.fetch(parentDescriptor).first {
                task.parent = parent
            }
        }
    }

    // MARK: - Delete Stale Items

    private func deleteStaleItems<T: PersistentModel>(_ type: T.Type, remoteIds: Set<String>, modelContext: ModelContext) where T: NotionSyncable {
        let descriptor = FetchDescriptor<T>()
        guard let locals = try? modelContext.fetch(descriptor) else { return }

        for item in locals {
            // Skip local-only items (e.g., sub-tasks)
            if let task = item as? TaskItem, task.isLocalOnly { continue }
            // Bug 4 fix: don't delete tasks with unsaved local edits
            if let task = item as? TaskItem, task.isDirty { continue }
            if !remoteIds.contains(item.notionPageId) {
                modelContext.delete(item)
            }
        }
    }

    // MARK: - Build Notion Properties for Push

    private func buildNotionProperties(for task: TaskItem, mappings: PropertyMappings) -> [String: Any] {
        var props: [String: Any] = [:]

        // Title
        props[mappings.taskTitleProperty] = [
            "title": [["text": ["content": task.title]]]
        ]

        // Status
        props[mappings.taskStatusProperty] = [
            "status": ["name": mappings.notionStatusName(for: task.status)]
        ]

        // Due Date
        if let dueDate = task.dueDate {
            let dateStr = shortDateFormatter.string(from: dueDate)
            props[mappings.taskDueDateProperty] = [
                "date": ["start": dateStr]
            ]
        } else {
            props[mappings.taskDueDateProperty] = [
                "date": NSNull()
            ]
        }

        // Target Date
        if let targetKey = mappings.taskTargetDateProperty {
            if let targetDate = task.targetDate {
                let dateStr = shortDateFormatter.string(from: targetDate)
                props[targetKey] = [
                    "date": ["start": dateStr]
                ]
            } else {
                props[targetKey] = [
                    "date": NSNull()
                ]
            }
        }

        // Parent relation for subtasks
        if let parentKey = mappings.taskParentProperty,
           let parentId = task.parentId {
            props[parentKey] = ["relation": [["id": parentId]]]
        }

        // Priority
        if let priorityKey = mappings.taskPriorityProperty {
            if let priority = task.priority {
                props[priorityKey] = ["select": ["name": priority.rawValue]]
            } else {
                props[priorityKey] = ["select": NSNull()]
            }
        }

        // Tags
        if let tagsKey = mappings.taskTagsProperty {
            let tagObjects = task.tags.map { ["name": $0] }
            props[tagsKey] = ["multi_select": tagObjects]
        }

        // Recurrence
        if let recurrenceKey = mappings.taskRecurrenceProperty {
            props[recurrenceKey] = ["select": ["name": task.recurrenceRaw]]
        }

        // Project Relation
        if let projectKey = mappings.taskProjectProperty {
            if let project = task.project {
                props[projectKey] = ["relation": [["id": project.notionPageId]]]
            } else {
                props[projectKey] = ["relation": []]
            }
        }

        return props
    }

    // MARK: - Helpers

    private func fetchSession(modelContext: ModelContext) -> UserSession? {
        let descriptor = FetchDescriptor<UserSession>()
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func refreshTaskStatusSchemaIfNeeded(
        for tasks: [TaskItem] = [],
        session: UserSession,
        currentMappings: PropertyMappings,
        forceRefresh: Bool
    ) async throws -> PropertyMappings {
        guard !session.tasksDatabaseId.isEmpty else { return currentMappings }

        let needsRefresh = forceRefresh || currentMappings.taskStatusSchema == nil || tasks.contains {
            currentMappings.taskStatusSchema?.hasOption(for: $0.status) != true
        }

        guard needsRefresh,
              let statusSchema = await fetchTaskStatusSchema(
                  databaseId: session.tasksDatabaseId,
                  propertyName: currentMappings.taskStatusProperty
              ) else {
            return currentMappings
        }

        var updatedMappings = currentMappings
        updatedMappings.taskStatusSchema = statusSchema
        session.propertyMappings = updatedMappings
        return updatedMappings
    }

    private func fetchTaskStatusSchema(databaseId: String, propertyName: String) async -> NotionStatusSchema? {
        guard let database = try? await api.retrieveDatabase(id: databaseId) else { return nil }
        return database.properties[propertyName]?.status
    }

    private func extractTitle(from page: NotionPage, propertyName: String) -> String {
        if let titleProp = page.properties[propertyName],
           let titleTexts = titleProp.title {
            return titleTexts.map(\.plainText).joined()
        }
        return "Untitled"
    }

    private func parseDate(_ string: String) -> Date? {
        // Full ISO8601 with time+timezone — already in correct absolute time
        if let date = dateFormatter.date(from: string) { return date }
        // Date-only: "2026-03-20" — ISO8601DateFormatter interprets this as UTC midnight,
        // which is wrong for users in non-UTC timezones. Parse as local calendar date instead.
        if string.count == 10, !string.contains("T") {
            var components = DateComponents()
            let parts = string.split(separator: "-")
            if parts.count == 3,
               let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
                components.year = year
                components.month = month
                components.day = day
                components.hour = 0
                components.minute = 0
                components.second = 0
                return Calendar.current.date(from: components)
            }
        }
        return nil
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
#endif
    }
}

// MARK: - NotionSyncable Protocol

protocol NotionSyncable {
    var notionPageId: String { get }
}

extension TaskItem: NotionSyncable {}
extension ProjectItem: NotionSyncable {}
