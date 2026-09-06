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
    private let timedDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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
            upsertProjects(projectPages, mappings: mappings, workspaceID: session.workspaceId, modelContext: modelContext)
        }

        if !session.tasksDatabaseId.isEmpty {
            let taskPages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: filter, sorts: nil)
            print("[Sync] Incremental: fetched \(taskPages.count) updated tasks")
            upsertTasks(taskPages, mappings: mappings, workspaceID: session.workspaceId, modelContext: modelContext)
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

            upsertProjects(allProjectPages, mappings: mappings, workspaceID: session.workspaceId, modelContext: modelContext)
            deleteStaleItems(ProjectItem.self, remoteIds: remoteProjectIds, workspaceID: session.workspaceId, modelContext: modelContext)
        } else {
            print("[Sync] No projects DB configured, skipping")
        }

        if !session.tasksDatabaseId.isEmpty {
            print("[Sync] Fetching tasks from DB: \(session.tasksDatabaseId)")
            let allTaskPages = try await api.queryAllPages(databaseId: session.tasksDatabaseId, filter: nil, sorts: nil)
            print("[Sync] Fetched \(allTaskPages.count) task pages from Notion")
            let remoteTaskIds = Set(allTaskPages.map(\.id))

            upsertTasks(allTaskPages, mappings: mappings, workspaceID: session.workspaceId, modelContext: modelContext)
            deleteStaleItems(TaskItem.self, remoteIds: remoteTaskIds, workspaceID: session.workspaceId, modelContext: modelContext)

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
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDirty == true })
        let dirtyTasks = try modelContext.fetch(descriptor).filter {
            $0.providerWorkspaceId == session.workspaceId
        }

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
        if task.isDeleted {
            if task.lastSyncedAt != nil {
                try await api.archivePage(pageId: task.externalTaskID)
            }
            modelContext.delete(task)
            try modelContext.save()
            return
        }

        let properties = buildNotionProperties(for: task, mappings: mappings)
        if task.lastSyncedAt == nil, !session.tasksDatabaseId.isEmpty {
            let created = try await api.createPage(databaseId: session.tasksDatabaseId, properties: properties)
            task.externalTaskID = created.id
        } else if task.lastSyncedAt == nil {
            return
        } else {
            _ = try await api.updatePage(pageId: task.externalTaskID, properties: properties)
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

    private func upsertProjects(
        _ pages: [NotionPage],
        mappings: PropertyMappings,
        workspaceID: String,
        modelContext: ModelContext
    ) {
        for page in pages {
            let title = extractTitle(from: page, propertyName: mappings.projectTitleProperty)
            let editedTime = parseDate(page.lastEditedTime)
            let emoji = page.icon?.emoji

            let pageId = page.id
            let descriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate<ProjectItem> { item in
                item.externalProjectID == pageId && item.providerWorkspaceId == workspaceID
            })

            if let existing = (try? modelContext.fetch(descriptor))?.first {
                existing.title = title
                existing.iconEmoji = emoji
                existing.providerWorkspaceId = workspaceID
                existing.lastEditedTime = editedTime
                existing.lastSyncedAt = Date()
            } else {
                let project = ProjectItem(externalProjectID: page.id, title: title, iconEmoji: emoji)
                project.providerWorkspaceId = workspaceID
                project.lastEditedTime = editedTime
                project.lastSyncedAt = Date()
                modelContext.insert(project)
            }
        }
    }

    // MARK: - Upsert Tasks

    private func upsertTasks(
        _ pages: [NotionPage],
        mappings: PropertyMappings,
        workspaceID: String,
        modelContext: ModelContext
    ) {
        for page in pages {
            let title = extractTitle(from: page, propertyName: mappings.taskTitleProperty)
            let editedTime = parseDate(page.lastEditedTime)

            let pageId = page.id
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { item in
                item.externalTaskID == pageId && item.providerWorkspaceId == workspaceID
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
                task = TaskItem(externalTaskID: page.id, title: title)
                modelContext.insert(task)
            }

            task.title = title
            task.providerWorkspaceId = workspaceID
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

            // The Notion "Due Date" property stores the deadline.
            if let dateProp = page.properties[mappings.taskDeadlineProperty],
               let dateStr = dateProp.date?.start {
                if let endStr = dateProp.date?.end {
                    task.plannedDay = parseDate(dateStr)
                    task.plannedDayHasTime = dateStr.contains("T")
                    task.deadline = parseDate(endStr)
                    task.deadlineHasTime = endStr.contains("T")
                } else {
                    task.deadline = parseDate(dateStr)
                    task.deadlineHasTime = dateStr.contains("T")
                }
            } else {
                task.deadline = nil
                task.deadlineHasTime = false
            }

            // The optional Notion "Target" property stores the planned day.
            if let targetKey = mappings.taskPlannedDayProperty,
               let targetProp = page.properties[targetKey],
               let targetStr = targetProp.date?.start {
                task.plannedDay = parseDate(targetStr)
                task.plannedDayHasTime = targetStr.contains("T")
            }

            task.validatePlannedDay()
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
                    item.externalProjectID == relationId && item.providerWorkspaceId == workspaceID
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
                    item.externalTaskID == parentId && item.providerWorkspaceId == workspaceID
                })
                task.parent = (try? modelContext.fetch(parentDescriptor))?.first
            } else if task.parentId == nil {
                task.parent = nil
            }
        }

        linkPendingSubtaskParents(workspaceID: workspaceID, modelContext: modelContext)
    }

    private func linkPendingSubtaskParents(workspaceID: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate {
            $0.parentId != nil && $0.providerWorkspaceId == workspaceID
        })
        guard let tasks = try? modelContext.fetch(descriptor) else { return }

        for task in tasks {
            guard let parentId = task.parentId else { continue }
            let parentDescriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { item in
                item.externalTaskID == parentId && item.providerWorkspaceId == workspaceID
            })
            if let parent = try? modelContext.fetch(parentDescriptor).first {
                task.parent = parent
            }
        }
    }

    // MARK: - Delete Stale Items

    private func deleteStaleItems<T: PersistentModel>(
        _ type: T.Type,
        remoteIds: Set<String>,
        workspaceID: String? = nil,
        modelContext: ModelContext
    ) where T: ProviderSyncable {
        let descriptor = FetchDescriptor<T>()
        guard let locals = try? modelContext.fetch(descriptor) else { return }

        for item in locals {
            // Bug 4 fix: don't delete tasks with unsaved local edits
            if let task = item as? TaskItem {
                guard task.providerWorkspaceId == workspaceID else { continue }
                if task.isDirty { continue }
            }
            if let project = item as? ProjectItem {
                guard project.providerWorkspaceId == workspaceID else { continue }
            }
            if !remoteIds.contains(item.externalProviderID) {
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

        // Deadline and planned day
        if let deadline = task.deadline {
            let deadlineString = notionDateString(deadline, hasTime: task.deadlineHasTime)
            if mappings.taskPlannedDayProperty == nil, let plannedDay = task.plannedDay {
                props[mappings.taskDeadlineProperty] = [
                    "date": [
                        "start": notionDateString(plannedDay, hasTime: task.plannedDayHasTime),
                        "end": deadlineString,
                    ]
                ]
            } else {
                props[mappings.taskDeadlineProperty] = [
                    "date": ["start": deadlineString]
                ]
            }
        } else {
            props[mappings.taskDeadlineProperty] = [
                "date": NSNull()
            ]
        }

        // Optional Notion "Target" property
        if let targetKey = mappings.taskPlannedDayProperty {
            if let plannedDay = task.plannedDay {
                props[targetKey] = [
                    "date": [
                        "start": notionDateString(plannedDay, hasTime: task.plannedDayHasTime)
                    ]
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
                props[projectKey] = ["relation": [["id": project.externalProjectID]]]
            } else {
                props[projectKey] = ["relation": []]
            }
        }

        return props
    }

    // MARK: - Helpers

    private func fetchSession(modelContext: ModelContext) -> UserSession? {
        let descriptor = FetchDescriptor<UserSession>()
        let sessions = try? modelContext.fetch(descriptor)
        guard let selected = sessions?.selectedProviderWorkspace,
              selected.providerIdentity == .notion else { return nil }
        return selected
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
        if let date = timedDateFormatter.date(from: string) { return date }
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

    private func notionDateString(_ date: Date, hasTime: Bool) -> String {
        hasTime ? timedDateFormatter.string(from: date) : shortDateFormatter.string(from: date)
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
#endif
    }
}

// MARK: - ProviderSyncable Protocol

protocol ProviderSyncable {
    var externalProviderID: String { get }
}

extension TaskItem: ProviderSyncable {
    var externalProviderID: String { externalTaskID }
}

extension ProjectItem: ProviderSyncable {
    var externalProviderID: String { externalProjectID }
}
