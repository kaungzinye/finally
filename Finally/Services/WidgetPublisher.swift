import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

extension WidgetSnapshot {
    /// The Daily Focus picks from any provider with their open steps, the selected workspace's open
    /// dated tasks, and the tasks it finished on their day. Widgets never list an unscheduled task.
    init(
        tasks: [TaskItem],
        focus: DailyFocus?,
        workspace: UserSession?,
        at referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        var positions: [ObjectIdentifier: Int] = [:]
        // Each open pick's open steps in order, then the pick, so a widget completion can hand
        // the pick's place to the next one.
        var nextInFocus: [ObjectIdentifier: TaskItem] = [:]
        var inFocus: Set<ObjectIdentifier> = []
        for (index, item) in (focus?.resolvedPicks(among: tasks) ?? []).enumerated() {
            guard let task = item.task else { continue }
            let chain = task.isOpen
                ? task.activeSubtasks.filter(\.isOpen).sorted { $0.sortIndex < $1.sortIndex } + [task]
                : [task]
            guard positions[ObjectIdentifier(chain[0])] == nil else { continue }
            positions[ObjectIdentifier(chain[0])] = index + 1
            inFocus.formUnion(chain.map(ObjectIdentifier.init))
            for (current, next) in zip(chain, chain.dropFirst()) {
                nextInFocus[ObjectIdentifier(current)] = next
            }
        }
        let today = calendar.startOfDay(for: referenceDate)
        func isOn(_ date: Date?) -> Bool { date.map { calendar.startOfDay(for: $0) == today } ?? false }
        let shown = tasks.filter { task in
            if inFocus.contains(ObjectIdentifier(task)) { return true }
            guard task.belongs(to: workspace), !task.isDeleted else { return false }
            if task.status == .done { return isOn(task.scheduledDay) || isOn(task.deadline) }
            return task.scheduledDay != nil || task.deadline != nil || (task.isSubtask && task.effectiveSuggestedDate != nil)
        }
        self.init(
            workspaceID: workspace?.workspaceId ?? "",
            focusDay: focus?.day,
            focusLimit: focus?.focusLimit ?? DailyFocus.defaultFocusLimit,
            focusPickCount: focus?.picks.count ?? 0,
            tasks: shown.map {
                WidgetTask($0, focusPosition: positions[ObjectIdentifier($0)], nextInFocus: nextInFocus[ObjectIdentifier($0)])
            }
        )
    }
}

private extension WidgetTask {
    init(_ task: TaskItem, focusPosition: Int?, nextInFocus: TaskItem?) {
        self.init(
            providerWorkspaceID: task.providerWorkspaceId ?? "",
            externalTaskID: task.externalTaskID,
            title: task.title,
            priority: task.priority,
            status: task.status,
            scheduledDay: task.scheduledDay,
            deadline: task.deadline,
            deadlineHasTime: task.deadlineHasTime,
            focusPosition: focusPosition,
            nextFocusTaskID: nextInFocus.map { "\($0.providerWorkspaceId ?? ""):\($0.externalTaskID)" },
            isSubtask: task.isSubtask,
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
        storage.snapshot = WidgetSnapshot(tasks: tasks, focus: focus, workspace: workspace, at: referenceDate)
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
        // Repeated taps on one task complete it once, so a recurring obligation advances one cycle.
        var seen: Set<WidgetCompletion> = []
        let completions = pending.map(\.completion).filter { seen.insert($0).inserted }
        let completed = completions.compactMap { completion in
            tasks.first {
                $0.providerWorkspaceId == completion.providerWorkspaceID
                    && $0.externalTaskID == completion.externalTaskID
                    && $0.isOpen
            }
        }
        completed.forEach { $0.complete() }
        try store.save()
        storage.removePendingCompletions(pending)
        try publish(store: store, storage: storage)
        return completed
    }
}
