import Foundation
import SwiftData

/// One task reference inside a Daily Focus. Picks point at tasks by provider workspace and
/// external identity so a Daily Focus can hold tasks from more than one provider.
struct DailyFocusPick: Codable, Hashable, Sendable {
    let providerWorkspaceID: String
    let externalTaskID: String
}

enum DailyFocusError: LocalizedError, Equatable {
    case full(limit: Int)
    case pickMissing
    case duplicatePick
    case taskUnavailable
    case needsSteps
    case needsNextDay

    var errorDescription: String? {
        switch self {
        case .full(let limit): "Choose a pick to replace. Daily Focus holds \(limit) picks."
        case .pickMissing: "This pick has changed. Review Daily Focus and try again."
        case .duplicatePick: "This task is already in Daily Focus."
        case .taskUnavailable: "This task is unavailable. You can drop its focus pick."
        case .needsSteps: "Add an unfinished step to this task, then finish breaking it down."
        case .needsNextDay: "Choose Daily Focus for a later day."
        }
    }
}

enum DailyFocusReplanningDecision {
    case keep
    case breakDown
    case schedule(Date)
    case deferTask
    case drop
}

/// The few tasks picked for one day, bounded by the focus limit.
@Model
final class DailyFocus {
    static let defaultFocusLimit = 3
    static let focusLimitRange = 1...5

    var day: Date
    var storageWorkspaceID: String
    var focusLimit: Int
    var isConfirmed: Bool = false
    var picksJSON: String = "[]"
    /// A local change not yet stored on Finally Server. Notion mode never sets it.
    var isDirty: Bool = false

    init(day: Date, focusLimit: Int = DailyFocus.defaultFocusLimit, storageWorkspaceID: String = "") {
        self.day = day
        self.storageWorkspaceID = storageWorkspaceID
        self.focusLimit = DailyFocus.clampedFocusLimit(focusLimit)
    }

    static func clampedFocusLimit(_ limit: Int) -> Int {
        min(max(limit, focusLimitRange.lowerBound), focusLimitRange.upperBound)
    }

    /// The calendar date Finally Server keys a Daily Focus by.
    static func dayKey(for day: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    var dayKey: String { DailyFocus.dayKey(for: day) }

    var picks: [DailyFocusPick] {
        get {
            guard let data = picksJSON.data(using: .utf8),
                  let picks = try? JSONDecoder().decode([DailyFocusPick].self, from: data) else { return [] }
            return picks
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8)
            picksJSON = String(decoding: data, as: UTF8.self)
        }
    }

    var isFull: Bool { picks.count >= focusLimit }

    func add(_ pick: DailyFocusPick) throws {
        var current = picks
        guard !current.contains(pick) else { return }
        guard current.count < focusLimit else { throw DailyFocusError.full(limit: focusLimit) }
        current.append(pick)
        picks = current
    }

    func remove(_ pick: DailyFocusPick) {
        picks = picks.filter { $0 != pick }
    }

    func replace(_ pick: DailyFocusPick, with replacement: DailyFocusPick) throws {
        var current = picks
        guard let index = current.firstIndex(of: pick) else { throw DailyFocusError.pickMissing }
        guard pick != replacement else { return }
        guard !current.contains(replacement) else { throw DailyFocusError.duplicatePick }
        current[index] = replacement
        picks = current
    }

    /// Applies one explicit decision. Validation finishes before either day's picks change.
    func replan(
        _ pick: DailyFocusPick,
        decision: DailyFocusReplanningDecision,
        task: TaskItem?,
        nextFocus: DailyFocus? = nil,
        displacing: DailyFocusPick? = nil
    ) throws {
        guard picks.contains(pick) else { throw DailyFocusError.pickMissing }
        if case .drop = decision {
            remove(pick)
            return
        }
        guard let task, !task.isDeleted, task.dailyFocusPick == pick else {
            throw DailyFocusError.taskUnavailable
        }
        switch decision {
        case .keep:
            guard let nextFocus, nextFocus.storageWorkspaceID == storageWorkspaceID, nextFocus.day > day else { throw DailyFocusError.needsNextDay }
            if !nextFocus.picks.contains(pick) {
                if let displacing {
                    try nextFocus.replace(displacing, with: pick)
                } else {
                    try nextFocus.add(pick)
                }
            }
            nextFocus.isConfirmed = false
        case .breakDown:
            guard task.nextActionableSubtask != nil else { throw DailyFocusError.needsSteps }
        case .schedule(let date):
            task.plannedDay = Calendar.current.startOfDay(for: date)
            task.isDirty = true
            SubtaskScheduler.distributeSubtaskDates(parent: task)
        case .deferTask:
            task.plannedDay = nil
            task.isDirty = true
            SubtaskScheduler.distributeSubtaskDates(parent: task)
        case .drop:
            break
        }
        remove(pick)
    }

    func remove(atOffsets offsets: IndexSet) {
        picks = picks.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var current = picks
        current.move(fromOffsets: source, toOffset: destination)
        picks = current
    }

    func confirm() {
        isConfirmed = true
    }
}

/// A pick paired with the local task it points at, or nothing when that task is gone.
struct ResolvedDailyFocusPick: Identifiable {
    let pick: DailyFocusPick
    let task: TaskItem?

    var id: DailyFocusPick { pick }
    var isAvailable: Bool { task != nil }
}

extension DailyFocus {
    func executionPicks(among tasks: [TaskItem]) -> [ResolvedDailyFocusPick] {
        var shown: Set<DailyFocusPick> = []
        return resolvedPicks(among: tasks).compactMap { item in
            guard let task = item.task, task.status != .done else { return nil }
            let action = task.nextActionableSubtask ?? task
            guard shown.insert(action.dailyFocusPick).inserted else { return nil }
            return ResolvedDailyFocusPick(pick: item.pick, task: action)
        }
    }

    func resolvedPicks(in store: ModelContext) throws -> [ResolvedDailyFocusPick] {
        resolvedPicks(among: try store.fetch(FetchDescriptor<TaskItem>()))
    }

    func resolvedPicks(among tasks: [TaskItem]) -> [ResolvedDailyFocusPick] {
        let picks = picks
        let externalIDs = Set(picks.map(\.externalTaskID))
        let tasksByPick = Dictionary(
            tasks.compactMap { task -> (DailyFocusPick, TaskItem)? in
                guard !task.isDeleted, externalIDs.contains(task.externalTaskID),
                      let workspaceID = task.providerWorkspaceId else { return nil }
                return (DailyFocusPick(providerWorkspaceID: workspaceID, externalTaskID: task.externalTaskID), task)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return picks.map { ResolvedDailyFocusPick(pick: $0, task: tasksByPick[$0]) }
    }
}

extension TaskItem {
    /// The reference a Daily Focus keeps for this task.
    var dailyFocusPick: DailyFocusPick {
        DailyFocusPick(providerWorkspaceID: providerWorkspaceId ?? "", externalTaskID: externalTaskID)
    }
}
