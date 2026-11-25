import Foundation

/// The Daily Focus as Today numbers it: one row per pick in pick order, then one empty slot per
/// open place up to the focus limit.
struct DailyFocusList {
    struct Row: Identifiable {
        let pick: DailyFocusPick
        let task: TaskItem?
        let number: Int
        /// The first open pick, where the user starts.
        let isNext: Bool

        /// A finished pick collapses to one short line in its place.
        var isDone: Bool { task?.status == .done }

        var id: DailyFocusPick { pick }
    }

    let rows: [Row]
    let emptySlotNumbers: [Int]

    /// The note beside the heading: the one counter, or a nudge to pick when nothing is picked.
    var status: String {
        guard !rows.isEmpty else { return "Pick from Today" }
        return "\(rows.filter(\.isDone).count) of \(rows.count) done"
    }

    init(focus: DailyFocus, tasks: [TaskItem]) {
        // An open picked parent shows its next step, as the Today widget does, and a task that
        // stands in for more than one pick shows once.
        var shown: Set<DailyFocusPick> = []
        let resolved = focus.resolvedPicks(among: tasks).compactMap { item -> ResolvedDailyFocusPick? in
            guard let task = item.task else { return item }
            let display = task.status == .done ? task : task.nextActionableSubtask ?? task
            guard shown.insert(display.dailyFocusPick).inserted else { return nil }
            return ResolvedDailyFocusPick(pick: item.pick, task: display)
        }
        let next = resolved.firstIndex { $0.task.map { $0.status != .done } ?? false }
        rows = resolved.enumerated().map { index, item in
            Row(pick: item.pick, task: item.task, number: index + 1, isNext: index == next)
        }
        let openSlots = max(focus.focusLimit - focus.picks.count, 0)
        let first = rows.count + 1
        emptySlotNumbers = Array(first..<first + openSlots)
    }

    /// A long press and drag moves a row among the rows, open or done. The new order saves into
    /// the pick order, and the empty slots stay after the last row.
    func move(in focus: DailyFocus, fromOffsets source: IndexSet, toOffset destination: Int) {
        focus.move(rows.map(\.pick), fromOffsets: source, toOffset: destination)
    }
}
