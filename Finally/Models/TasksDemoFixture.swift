#if DEBUG
import Foundation
import SwiftData

/// Seeds an in-memory store for the `-tasks-demo` launch argument: one Notion workspace with
/// Inbox tasks, a project holding more than three open tasks, a project with one undated task,
/// and an empty project.
enum TasksDemoFixture {
    static let workspaceID = "demo-tasks-workspace"

    static func makeContainer(referenceDate: Date = Date(), calendar: Calendar = .current) -> ModelContainer {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self, DailyFocus.self])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        } catch {
            fatalError("Tasks demo store failed: \(error)")
        }
        let context = ModelContext(container)
        seed(into: context, referenceDate: referenceDate, calendar: calendar)
        try? context.save()
        return container
    }

    static func seed(into context: ModelContext, referenceDate: Date, calendar: Calendar) {
        let workspace = UserSession(workspaceId: workspaceID, workspaceName: "Demo Notion", providerIdentity: .notion)
        context.insert(workspace)

        let today = calendar.startOfDay(for: referenceDate)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        let home = makeProject("demo-home", "Home", emoji: "🏡", in: context)
        let garden = makeProject("demo-garden", "Garden", emoji: nil, in: context)
        makeProject("demo-taxes", "Taxes", emoji: nil, in: context)

        makeTask("demo-receipts", "Sort the receipts", in: context)
        makeTask("demo-dentist", "Book the dentist", in: context).scheduledDay = day(2)

        makeTask("demo-boiler", "Service the boiler", project: home, in: context).deadline = day(3)
        makeTask("demo-shelves", "Hang the shelves", project: home, in: context).deadline = day(6)
        makeTask("demo-paint", "Choose paint colors", project: home, in: context).scheduledDay = day(1)
        makeTask("demo-gutters", "Clear the gutters", project: home, in: context).scheduledDay = day(4)
        makeTask("demo-lamp", "Fix the hall lamp", project: home, in: context)

        makeTask("demo-bulbs", "Plant the bulbs", project: garden, in: context)
    }

    @discardableResult
    private static func makeProject(_ id: String, _ title: String, emoji: String?, in context: ModelContext) -> ProjectItem {
        let project = ProjectItem(externalProjectID: id, title: title, iconEmoji: emoji)
        project.providerWorkspaceId = workspaceID
        context.insert(project)
        return project
    }

    @discardableResult
    private static func makeTask(_ id: String, _ title: String, project: ProjectItem? = nil, in context: ModelContext) -> TaskItem {
        let task = TaskItem(externalTaskID: id, title: title)
        task.providerWorkspaceId = workspaceID
        context.insert(task)
        task.project = project
        return task
    }
}
#endif
