import Foundation
import SwiftData

/// One task reference inside a Daily Focus. Picks point at tasks by provider workspace and
/// external identity so a Daily Focus can hold tasks from more than one provider.
struct DailyFocusPick: Codable, Hashable, Sendable {
    let providerWorkspaceID: String
    let externalTaskID: String
}

enum DailyFocusError: Error, Equatable {
    case full(limit: Int)
}

/// The few tasks picked for one day, bounded by the focus limit.
@Model
final class DailyFocus {
    static let defaultFocusLimit = 3
    static let focusLimitRange = 1...5

    var day: Date
    var focusLimit: Int
    var isConfirmed: Bool = false
    var picksJSON: String = "[]"
    /// A local change not yet stored on Finally Server. Notion mode never sets it.
    var isDirty: Bool = false

    init(day: Date, focusLimit: Int = DailyFocus.defaultFocusLimit) {
        self.day = day
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
