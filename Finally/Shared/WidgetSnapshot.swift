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
    var deadlineHasTime = false
    /// The task's place in today's Daily Focus, starting at 1. A step standing in for a picked
    /// parent takes the parent's place.
    var focusPosition: Int?
    var isSubtask = false
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

/// The presentation snapshot of the selected provider workspace. The app writes it to app-group
/// storage after every local change and sync, and every widget draws from it.
struct WidgetSnapshot: Codable, Equatable {
    /// The day the Daily Focus picks belong to.
    var focusDay: Date?
    var focusLimit: Int
    /// Every pick, a deleted one included, so the picks count like the Today tab.
    var focusPickCount: Int
    var tasks: [WidgetTask]
}

/// A task the user finished from a widget, waiting for the app to apply it.
struct WidgetCompletion: Codable, Hashable {
    let providerWorkspaceID: String
    let externalTaskID: String
}

/// App-group storage shared by the app and the widget.
struct WidgetStorage {
    static let snapshotKey = "widgetSnapshot"
    static let pendingCompletionsKey = "pendingWidgetCompletions"

    let defaults: UserDefaults

    static var appGroup: WidgetStorage? {
        UserDefaults(suiteName: AppConstants.appGroupID).map(WidgetStorage.init)
    }

    var snapshot: WidgetSnapshot? {
        get {
            defaults.data(forKey: Self.snapshotKey).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        }
        nonmutating set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.snapshotKey)
        }
    }

    private(set) var pendingCompletions: [WidgetCompletion] {
        get {
            defaults.data(forKey: Self.pendingCompletionsKey)
                .flatMap { try? JSONDecoder().decode([WidgetCompletion].self, from: $0) } ?? []
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.pendingCompletionsKey)
        }
    }

    /// The widget's side of completing a task: record it for the app and show it done.
    func complete(_ completion: WidgetCompletion) {
        if !pendingCompletions.contains(completion) {
            pendingCompletions.append(completion)
        }
        guard var snapshot else { return }
        for index in snapshot.tasks.indices where snapshot.tasks[index].providerWorkspaceID == completion.providerWorkspaceID
            && snapshot.tasks[index].externalTaskID == completion.externalTaskID {
            snapshot.tasks[index].status = .done
        }
        self.snapshot = snapshot
    }

    /// Forgets completions the app has applied, keeping any the widget recorded since.
    func removePendingCompletions(_ applied: [WidgetCompletion]) {
        pendingCompletions.removeAll { applied.contains($0) }
    }
}
