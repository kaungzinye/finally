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
    /// The selected provider workspace. Every list but the Daily Focus picks holds only its tasks.
    var workspaceID: String
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
        for index in snapshot.tasks.indices where snapshot.tasks[index].providerWorkspaceID == completion.providerWorkspaceID
            && snapshot.tasks[index].externalTaskID == completion.externalTaskID {
            snapshot.tasks[index].status = .done
        }
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
