#if DEBUG
import Foundation
import SwiftData

/// Seeds an in-memory store for the `-tasks-demo` launch argument: one Notion workspace with
/// Inbox tasks, a project holding more than three open tasks, a project with one undated open task
/// and one complete task, and an empty project. Three Home tasks carry priorities, one is in progress,
/// and the boiler sits in the window between its scheduled day and its deadline.
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

        let boiler = makeTask("demo-boiler", "Service the boiler", project: home, in: context)
        boiler.scheduledDay = day(0)
        boiler.deadline = day(3)
        boiler.priority = .high
        let shelves = makeTask("demo-shelves", "Hang the shelves", project: home, in: context)
        shelves.deadline = day(6)
        shelves.status = .inProgress
        shelves.priority = .medium
        let paint = makeTask("demo-paint", "Choose paint colors", project: home, in: context)
        paint.scheduledDay = day(1)
        paint.priority = .urgent
        makeTask("demo-gutters", "Clear the gutters", project: home, in: context).scheduledDay = day(4)
        makeTask("demo-lamp", "Fix the hall lamp", project: home, in: context)

        makeTask("demo-bulbs", "Plant the bulbs", project: garden, in: context)
        makeTask("demo-lawn", "Mow the lawn", project: garden, in: context).status = .done
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
