import Foundation

/// One task as the widgets see it: what the rows draw and what the shared Today query reads.
struct WidgetTask: Codable, Equatable, Identifiable {
    let providerWorkspaceID: String
    let externalTaskID: String
    let title: String
    let priority: TaskPriority?
    var status: TaskStatus
    let scheduledDay: Date?
    let deadline: Date?
    /// When the task finished, or nil while it is open.
    var completedAt: Date?
    var deadlineHasTime = false
    /// The external ID of the parent this task is a step of, in the same provider workspace.
    var parentID: String?
    var isSubtask: Bool { parentID != nil }
    var suggestedDate: Date?
    var hasOpenSubtasks = false

    var id: String { "\(providerWorkspaceID):\(externalTaskID)" }
}

extension WidgetTask {
    /// Opens the task in its own provider workspace.
    var url: URL {
        var components = URLComponents()
        components.scheme = AppConstants.urlScheme
        components.host = "tasks"
        components.path = "/" + externalTaskID
        components.queryItems = [URLQueryItem(name: "workspace", value: providerWorkspaceID)]
        return components.url ?? URL(string: "\(AppConstants.urlScheme)://")!
    }
}

extension WidgetTask: TodayTask {
    var isOpen: Bool { status != .done }
    var priorityRank: Int { priority?.sortOrder ?? TaskPriority.allCases.count }
    var effectiveSuggestedDate: Date? { suggestedDate }
}

/// One Daily Focus pick as the widgets track it.
struct WidgetFocusPlace: Codable, Equatable {
    /// The pick's place in today's Daily Focus, starting at 1.
    let position: Int
    /// The `id`s of the tasks that hold this place in turn: an open picked parent's open steps in
    /// order, then the parent. The first one is shown.
    var taskIDs: [String]
}

/// The presentation snapshot of the selected provider workspace. The app writes it to app-group
/// storage after every local change and sync, and every widget draws from it.
struct WidgetSnapshot: Codable, Equatable {
    /// The selected provider workspace. Every list but the Daily Focus picks holds only its tasks.
    var workspaceID: String
    /// The day the Daily Focus picks belong to.
    var focusDay: Date?
    var focusLimit: Int
    /// Every pick, a deleted one included, so the picks count like the Today tab.
    var focusPickCount: Int
    /// The user confirmed the Daily Focus. A day the personal agent proposed waits for the user,
    /// so the widgets show its picks for review and offer no completion.
    var isFocusConfirmed: Bool
    /// The picks the widgets show, one per resolved pick, in pick order.
    var focusPlaces: [WidgetFocusPlace] = []
    var tasks: [WidgetTask]
}

extension WidgetSnapshot {
    /// The moments the widgets redraw this snapshot: now, one second after each open task's timed
    /// deadline still to come today so it turns overdue on time, and the next midnight.
    func timelineDates(from now: Date, calendar: Calendar = .current) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let deadlines = tasks
            .filter { $0.isOpen && $0.deadlineHasTime }
            .compactMap(\.deadline)
            .filter { $0 >= now && $0 < midnight }
            .map { $0.addingTimeInterval(1) }
        return [now] + Set(deadlines).sorted() + [midnight]
    }

    /// Shows a widget completion at `date`: the task turns done, a parent whose last open step finished
    /// returns to Today, and a finished step hands its Daily Focus place to the next open task in
    /// its pick, as the app does.
    mutating func complete(_ completion: WidgetCompletion, at date: Date = Date()) {
        for index in tasks.indices where tasks[index].providerWorkspaceID == completion.providerWorkspaceID
            && tasks[index].externalTaskID == completion.externalTaskID && tasks[index].isOpen {
            tasks[index].status = .done
            tasks[index].completedAt = date
            if let parentID = tasks[index].parentID {
                refreshOpenSteps(ofParent: parentID, in: completion.providerWorkspaceID)
            }
            passFocusPlaces(from: tasks[index].id)
        }
    }

    /// Sets whether the parent still has an open step among its steps in the snapshot. A dated
    /// parent's open steps all carry a suggested date, so the snapshot holds every one of them.
    private mutating func refreshOpenSteps(ofParent parentID: String, in workspaceID: String) {
        let hasOpenSteps = tasks.contains {
            $0.providerWorkspaceID == workspaceID && $0.parentID == parentID && $0.isOpen
        }
        for index in tasks.indices where tasks[index].providerWorkspaceID == workspaceID
            && tasks[index].externalTaskID == parentID {
            tasks[index].hasOpenSubtasks = hasOpenSteps
        }
    }

    /// Moves each Daily Focus place the finished task held to the first open task after it in
    /// that place. A place stays put when no open task remains in it.
    private mutating func passFocusPlaces(from taskID: String) {
        let openIDs = Set(tasks.filter(\.isOpen).map(\.id))
        for index in focusPlaces.indices where focusPlaces[index].taskIDs.first == taskID {
            if let next = focusPlaces[index].taskIDs.dropFirst().firstIndex(where: openIDs.contains) {
                focusPlaces[index].taskIDs.removeFirst(next)
            }
        }
    }
}

/// A task the user finished from a widget, waiting for the app to apply it.
struct WidgetCompletion: Codable, Hashable {
    let providerWorkspaceID: String
    let externalTaskID: String
}

/// A widget completion as stored: one file per tap, named by `id`.
struct PendingWidgetCompletion: Equatable {
    let id: String
    let completion: WidgetCompletion
}

/// App-group storage shared by the app and the widget. Each widget completion is its own file,
/// so the widget adds taps and the app removes the ones it applied without rewriting each other's.
struct WidgetStorage {
    static let snapshotKey = "widgetSnapshot"

    let defaults: UserDefaults
    let completionsDirectory: URL

    static var appGroup: WidgetStorage? {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID),
              let container = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
              ) else { return nil }
        return WidgetStorage(
            defaults: defaults,
            completionsDirectory: container.appending(path: "PendingWidgetCompletions", directoryHint: .isDirectory)
        )
    }

    var snapshot: WidgetSnapshot? {
        get {
            defaults.data(forKey: Self.snapshotKey).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        }
        nonmutating set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.snapshotKey)
        }
    }

    var pendingCompletions: [PendingWidgetCompletion] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: completionsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let completion = try? JSONDecoder().decode(WidgetCompletion.self, from: data) else { return nil }
            return PendingWidgetCompletion(id: file.deletingPathExtension().lastPathComponent, completion: completion)
        }
    }

    /// The widget's side of completing a task: record it for the app and show it done.
    func complete(_ completion: WidgetCompletion) {
        if let data = try? JSONEncoder().encode(completion) {
            try? FileManager.default.createDirectory(at: completionsDirectory, withIntermediateDirectories: true)
            try? data.write(to: file(for: UUID().uuidString), options: .atomic)
        }
        guard var snapshot else { return }
        snapshot.complete(completion)
        self.snapshot = snapshot
    }

    /// Forgets the completions the app applied. Any the widget recorded since stay pending.
    func removePendingCompletions(_ applied: [PendingWidgetCompletion]) {
        for entry in applied {
            try? FileManager.default.removeItem(at: file(for: entry.id))
        }
    }

    private func file(for id: String) -> URL {
        completionsDirectory.appending(path: id + ".json")
    }
}
