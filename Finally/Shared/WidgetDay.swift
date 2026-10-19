import Foundation

/// The day the widgets draw from one snapshot at one moment. It reads the shared Today query, so
/// every widget agrees with the Today tab.
struct WidgetDay {
    let focusLimit: Int
    let focusPickCount: Int
    /// Today's Daily Focus picks in pick order, finished ones included. Two picks can show one
    /// task, such as a picked step that is also its picked parent's next step.
    let picks: [WidgetTask]
    /// The picks of a Daily Focus the personal agent proposed and the user has yet to confirm, in
    /// pick order, each task once. They are not picks until the user confirms them.
    let unconfirmedPicks: [WidgetTask]
    /// Each pick's place in Daily Focus, matching `picks` by index.
    private let pickPositions: [Int]
    /// The rest of Today in Today order, never repeating a pick.
    let otherTasks: [Today.Member<WidgetTask>]
    /// Open tasks dated in the next seven days and not in Today, ordered by their first date there.
    let comingUp: [WidgetTask]
    /// Tasks finished today that are not picks: scheduled or due today, then done.
    let finishedToday: [WidgetTask]

    init(snapshot: WidgetSnapshot, at date: Date, calendar: Calendar = .current) {
        let isToday = snapshot.focusDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        focusLimit = snapshot.focusLimit
        focusPickCount = isToday ? snapshot.focusPickCount : 0
        let tasksByID = Dictionary(snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let places = isToday
            ? snapshot.focusPlaces.sorted { $0.position < $1.position }.compactMap { place in
                place.taskIDs.first.flatMap { tasksByID[$0] }.map { (position: place.position, task: $0) }
            }
            : []
        let confirmedPlaces = snapshot.isFocusConfirmed ? places : []
        var seenUnconfirmed: Set<String> = []
        unconfirmedPicks = snapshot.isFocusConfirmed
            ? []
            : places.map(\.task).filter { seenUnconfirmed.insert($0.id).inserted }
        let picks = confirmedPlaces.map(\.task)
        pickPositions = confirmedPlaces.map(\.position)
        let pickIDs = Set(picks.map(\.id))
        // Picks span workspaces. Everything else matches the Today tab's selected workspace.
        let scoped = snapshot.tasks.filter { $0.providerWorkspaceID == snapshot.workspaceID }
        let otherTasks = Today.members(of: scoped, at: date, calendar: calendar) { pickIDs.contains($0.id) }
        self.picks = picks
        self.otherTasks = otherTasks

        let today = calendar.startOfDay(for: date)
        let lastDay = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let todayIDs = pickIDs.union(otherTasks.map(\.task.id))
        finishedToday = scoped.filter { task in
            guard !task.isOpen, !pickIDs.contains(task.id) else { return false }
            return [task.scheduledDay, task.deadline].contains { $0.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
        }
        comingUp = scoped
            .compactMap { task -> (task: WidgetTask, day: Date)? in
                guard task.isOpen, !task.isSubtask, !todayIDs.contains(task.id) else { return nil }
                let days = [task.scheduledDay, task.deadline].compactMap { $0.map(calendar.startOfDay) }
                return days.filter { $0 > today && $0 <= lastDay }.min().map { (task, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day { return lhs.day < rhs.day }
                if lhs.task.priorityRank != rhs.task.priorityRank { return lhs.task.priorityRank < rhs.task.priorityRank }
                return lhs.task.title.localizedStandardCompare(rhs.task.title) == .orderedAscending
            }
            .map(\.task)
    }

    var focusHeading: String { DailyFocusHeading.text(focusLimit: focusLimit) }

    /// Today's Daily Focus waits for the user's confirmation, so the focus and now widgets show its
    /// picks for review instead of work to do.
    var awaitsConfirmation: Bool { !unconfirmedPicks.isEmpty }

    /// The review heading, such as "3 things to confirm".
    var confirmHeading: String {
        unconfirmedPicks.count == 1 ? "1 thing to confirm" : "\(unconfirmedPicks.count) things to confirm"
    }

    /// The open picks, each task once.
    var openPicks: [WidgetTask] {
        var seen: Set<String> = []
        return picks.filter { $0.isOpen && seen.insert($0.id).inserted }
    }

    /// The pick to work on now: the first open one.
    var nowPick: WidgetTask? { openPicks.first }

    /// Where the now pick sits among the picks, such as "2 of 3".
    var nowPickPlace: String? {
        picks.firstIndex(where: \.isOpen).map { "\(pickPositions[$0]) of \(focusPickCount)" }
    }

    /// All of Today in Today-tab order: the open picks, then the other tasks.
    var today: [WidgetTask] { openPicks + otherTasks.map(\.task) }

    /// The lock screen ring: one section per task in Today, the picks first, each filled once done.
    var ringSections: [RingSection] {
        picks.map { RingSection(isFocus: true, isDone: !$0.isOpen) }
            + otherTasks.map { _ in RingSection(isFocus: false, isDone: false) }
            + finishedToday.map { _ in RingSection(isFocus: false, isDone: true) }
    }

    /// The today widget's rows: all of Today, then Coming up while rows remain. When Today
    /// overflows, the last row reads "+N more" instead.
    func todayWidgetLayout(rows: Int) -> TodayWidgetLayout {
        let today = today
        if today.count > rows {
            let shown = max(rows - 1, 0)
            return TodayWidgetLayout(today: Array(today.prefix(shown)), moreCount: today.count - shown, comingUp: [])
        }
        // The "Coming up" label takes a row of its own.
        let room = rows - today.count - 1
        return TodayWidgetLayout(today: today, moreCount: 0, comingUp: Array(comingUp.prefix(max(room, 0))))
    }
}

struct RingSection: Equatable {
    /// A Daily Focus pick draws in ink, every other task in a second color.
    let isFocus: Bool
    let isDone: Bool
}

struct TodayWidgetLayout: Equatable {
    let today: [WidgetTask]
    /// The Today tasks left out for room.
    let moreCount: Int
    let comingUp: [WidgetTask]
}
