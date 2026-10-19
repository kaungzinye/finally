import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

extension WidgetSnapshot {
    /// The Daily Focus picks from any provider with their open steps, the selected workspace's open
    /// dated tasks, and the tasks it finished today out of Today. Widgets never list an unscheduled task.
    init(
        tasks: [TaskItem],
        focus: DailyFocus?,
        workspace: UserSession?,
        at referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        // Each open pick holds its open steps in order, then itself, so a widget completion can
        // hand the pick's place to the next one.
        var places: [WidgetFocusPlace] = []
        var inFocus: Set<ObjectIdentifier> = []
        for (index, item) in (focus?.resolvedPicks(among: tasks) ?? []).enumerated() {
            guard let task = item.task else { continue }
            let chain = task.isOpen
                ? task.activeSubtasks.filter(\.isOpen).sorted { $0.sortIndex < $1.sortIndex } + [task]
                : [task]
            places.append(WidgetFocusPlace(position: index + 1, taskIDs: chain.map(\.widgetTaskID)))
            inFocus.formUnion(chain.map(ObjectIdentifier.init))
        }
        let shown = tasks.filter { task in
            if inFocus.contains(ObjectIdentifier(task)) { return true }
            guard task.belongs(to: workspace), !task.isDeleted else { return false }
            if task.status == .done { return Today.finishedReason(for: task, at: referenceDate, calendar: calendar) != nil }
            return task.scheduledDay != nil || task.deadline != nil || (task.isSubtask && task.effectiveSuggestedDate != nil)
        }
        self.init(
            workspaceID: workspace?.workspaceId ?? "",
            focusDay: focus?.day,
            focusLimit: focus?.focusLimit ?? DailyFocus.defaultFocusLimit,
            focusPickCount: focus?.picks.count ?? 0,
            isFocusConfirmed: focus?.isConfirmed ?? false,
            focusPlaces: places,
            tasks: shown.map(WidgetTask.init)
        )
    }
}

private extension TaskItem {
    /// The `id` this task's `WidgetTask` carries.
    var widgetTaskID: String { "\(providerWorkspaceId ?? ""):\(externalTaskID)" }
}

private extension WidgetTask {
    init(_ task: TaskItem) {
        self.init(
            providerWorkspaceID: task.providerWorkspaceId ?? "",
            externalTaskID: task.externalTaskID,
            title: task.title,
            priority: task.priority,
            status: task.status,
            scheduledDay: task.scheduledDay,
            deadline: task.deadline,
            completedAt: task.completedAt,
            deadlineHasTime: task.deadlineHasTime,
            parentID: task.parentId,
            suggestedDate: task.isSubtask ? task.effectiveSuggestedDate : nil,
            hasOpenSubtasks: task.hasOpenSubtasks
        )
    }
}

/// Writes the widget snapshot and reloads the widgets.
enum WidgetPublisher {
    static func publish(store: ModelContext, storage: WidgetStorage? = .appGroup, at referenceDate: Date = Date()) throws {
        guard let storage else { return }
        let workspace = try store.selectedProviderWorkspace()
        let workspaceID = workspace?.workspaceId ?? ""
        let day = Calendar.current.startOfDay(for: referenceDate)
        let focus = try store.fetch(FetchDescriptor<DailyFocus>(
            predicate: #Predicate { $0.day == day && $0.storageWorkspaceID == workspaceID }
        )).first
        let tasks = try store.fetch(FetchDescriptor<TaskItem>())
        var snapshot = WidgetSnapshot(tasks: tasks, focus: focus, workspace: workspace, at: referenceDate)
        // Completions the app has yet to apply stay done on the widget, finished at their first tap.
        snapshot.complete(storage.pendingCompletions)
        storage.snapshot = snapshot
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }

    /// Applies the completions recorded from widgets as dirty edits, clears them, and rewrites the
    /// snapshot. A completion for a task that is already done or gone changes nothing. The caller
    /// reschedules reminders and syncs.
    @discardableResult
    static func applyPendingCompletions(store: ModelContext, storage: WidgetStorage? = .appGroup) throws -> [TaskItem] {
        guard let storage else { return [] }
        let pending = storage.pendingCompletions
        guard !pending.isEmpty else { return [] }
        let tasks = try store.fetch(FetchDescriptor<TaskItem>())
        // Repeated taps on one task complete it once, at the first tap, so a recurring obligation
        // advances one cycle.
        let completions = Dictionary(grouping: pending.map(\.completion), by: \.taskID)
            .values.compactMap { $0.min { $0.completedAt < $1.completedAt } }
            .sorted { $0.completedAt < $1.completedAt }
        var completed: [TaskItem] = []
        for completion in completions {
            guard let task = tasks.first(where: {
                $0.providerWorkspaceId == completion.providerWorkspaceID
                    && $0.externalTaskID == completion.externalTaskID
                    && $0.isOpen
            }) else { continue }
            task.complete(at: completion.completedAt)
            completed.append(task)
        }
        try store.save()
        storage.removePendingCompletions(pending)
        try publish(store: store, storage: storage)
        return completed
    }
}
