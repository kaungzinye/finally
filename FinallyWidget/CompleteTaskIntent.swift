import AppIntents
import WidgetKit

/// Finishes a task from a widget. It records the completion for the app and shows the task done.
/// The app applies the completion on launch and on foreground.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete task"
    static let isDiscoverable = false

    @Parameter(title: "Workspace")
    var providerWorkspaceID: String

    @Parameter(title: "Task")
    var externalTaskID: String

    init() {}

    init(task: WidgetTask) {
        providerWorkspaceID = task.providerWorkspaceID
        externalTaskID = task.externalTaskID
    }

    func perform() async throws -> some IntentResult {
        WidgetStorage.appGroup?.complete(
            WidgetCompletion(providerWorkspaceID: providerWorkspaceID, externalTaskID: externalTaskID)
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
