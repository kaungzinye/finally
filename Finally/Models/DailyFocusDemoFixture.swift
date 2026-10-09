#if DEBUG
import Foundation
import SwiftData

/// Seeds an in-memory store for the `-daily-focus-demo` launch argument: a selected Notion
/// workspace, a Finally Server workspace, open tasks in both, and a full Daily Focus whose picks
/// span both providers and include one unavailable task.
enum DailyFocusDemoFixture {
    static let notionWorkspaceID = "demo-notion-workspace"
    static let serverWorkspaceID = "demo-server-workspace"

    static func makeContainer(referenceDate: Date = Date(), calendar: Calendar = .current) -> ModelContainer {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Daily Focus demo store failed: \(error)")
        }
        let context = ModelContext(container)
        seed(into: context, referenceDate: referenceDate, calendar: calendar)
        try? context.save()
        return container
    }

    static func seed(into context: ModelContext, referenceDate: Date, calendar: Calendar) {
        let notion = UserSession(workspaceId: notionWorkspaceID, workspaceName: "Demo Notion", providerIdentity: .notion)
        notion.isSelected = true
        let server = UserSession(workspaceId: serverWorkspaceID, workspaceName: "Demo Server", providerIdentity: .finallyServer)
        server.isSelected = false
        server.serverBaseURL = "https://tasks.example.com"
        server.serverProjectID = 42
        context.insert(notion)
        context.insert(server)

        let today = calendar.startOfDay(for: referenceDate)
        let brief = makeTask("demo-brief", "Draft the brief", workspace: notionWorkspaceID, priority: .high)
        brief.deadline = today
        let bank = makeTask("demo-bank", "Call the bank", workspace: notionWorkspaceID, priority: .medium)
        bank.deadline = calendar.date(byAdding: .day, value: 2, to: today)
        let contract = makeTask("demo-contract", "Review the contract", workspace: notionWorkspaceID, priority: nil)
        contract.plannedDay = calendar.date(byAdding: .day, value: 1, to: today)
        let release = makeTask("demo-release", "Ship the release notes", workspace: serverWorkspaceID, priority: .urgent)
        release.deadline = calendar.date(byAdding: .day, value: 1, to: today)
        for task in [brief, bank, contract, release] {
            context.insert(task)
        }

        let focus = DailyFocus(day: today, focusLimit: 3, storageWorkspaceID: notionWorkspaceID)
        focus.picks = [
            brief.dailyFocusPick,
            release.dailyFocusPick,
            DailyFocusPick(providerWorkspaceID: notionWorkspaceID, externalTaskID: "demo-removed"),
        ]
        context.insert(focus)
    }

    private static func makeTask(_ id: String, _ title: String, workspace: String, priority: TaskPriority?) -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = workspace
        task.priority = priority
        return task
    }
}
#endif
