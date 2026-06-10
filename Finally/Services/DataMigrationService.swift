import Foundation
import SwiftData

/// One-time migrations for Phase 6B model changes.
enum DataMigrationService {
    private static let remindersMigratedKey = "phase6b.remindersMigrated"
    private static let fieldMigrationKey = "phase6b.fieldMigrationDone"

    @MainActor
    static func runIfNeeded(modelContext: ModelContext) {
        migrateLegacyFields(modelContext: modelContext)
        migrateReminderItems(modelContext: modelContext)
    }

    private static func migrateLegacyFields(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: fieldMigrationKey) else { return }
        guard let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) else { return }

        for task in tasks {
            if task.targetDate == nil, let legacyStart = task.startDate {
                task.targetDate = legacyStart
            }
            if task.suggestedDateOverride == nil, let legacySuggested = task.suggestedDate {
                task.suggestedDateOverride = legacySuggested
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: fieldMigrationKey)
    }

    private static func migrateReminderItems(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: remindersMigratedKey) else { return }

        guard let legacyReminders = try? modelContext.fetch(FetchDescriptor<ReminderItem>()) else { return }
        guard !legacyReminders.isEmpty else {
            UserDefaults.standard.set(true, forKey: remindersMigratedKey)
            return
        }

        var grouped: [String: [TaskReminder]] = [:]
        for item in legacyReminders {
            guard let task = item.task else { continue }
            guard let converted = TaskReminder.fromLegacy(
                intervalSeconds: item.intervalSeconds,
                absoluteDate: item.absoluteDate
            ) else { continue }
            grouped[task.notionPageId, default: []].append(converted)
        }

        for (pageId, reminders) in grouped {
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.notionPageId == pageId })
            guard let task = try? modelContext.fetch(descriptor).first else { continue }
            var merged = task.taskReminders
            for reminder in reminders where !merged.contains(where: { $0.id == reminder.id }) {
                merged.append(reminder)
            }
            task.taskReminders = merged
        }

        for item in legacyReminders {
            modelContext.delete(item)
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: remindersMigratedKey)
    }

    static func localOnlySubtasks(in modelContext: ModelContext) -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isLocalOnly == true && $0.parentId != nil })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @MainActor
    static func promoteLocalSubtasks(_ subtasks: [TaskItem], modelContext: ModelContext) {
        for subtask in subtasks {
            subtask.isLocalOnly = false
            subtask.isDirty = true
        }
        try? modelContext.save()
    }
}
