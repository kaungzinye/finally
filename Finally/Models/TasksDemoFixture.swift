#if DEBUG
import Foundation
import SwiftData

/// Seeds an in-memory store for the `-tasks-demo` launch argument: one Notion workspace with
/// Inbox tasks, a project holding more than three open tasks, a project with one undated open task
/// and one complete task, and an empty project. Three Home tasks carry priorities, one is in progress,
/// and the boiler sits in the window between its scheduled day and its deadline. The Inbox also
/// holds a timed deadline tomorrow and a deadline a year out.
///
/// `-demo-task-count N` adds N more tasks spread over ten more projects and the Inbox, with a mix
/// of statuses, priorities, dates, and subtasks, to profile the tabs over a realistic store.
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
        if let count = launchTaskCount {
            seedBulk(count, into: context, referenceDate: referenceDate, calendar: calendar)
        }
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
        let water = makeTask("demo-water", "Pay the water bill", in: context)
        water.deadline = calendar.date(byAdding: DateComponents(hour: 17, minute: 30), to: day(1))
        water.deadlineHasTime = true
        makeTask("demo-lease", "Renew the lease", in: context).deadline = day(365)

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

    /// The task count the `-demo-task-count` launch argument names.
    static var launchTaskCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo-task-count"), arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
    }

    /// Adds `count` tasks: one in eight sits in the Inbox, the rest spread over ten projects. One in
    /// five is complete and one in six in progress. Dates range from two weeks back to two months
    /// out, and every tenth task carries two subtasks.
    static func seedBulk(_ count: Int, into context: ModelContext, referenceDate: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: referenceDate)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let names = ["Work", "Errands", "Reading", "Fitness", "Travel", "Finance", "Kitchen", "Studio", "Family", "Learning"]
        let projects = names.enumerated().map { index, name in
            makeProject("bulk-project-\(index)", name, emoji: index.isMultiple(of: 3) ? "📁" : nil, in: context)
        }
        let verbs = ["Draft", "Review", "Book", "Plan", "Call about", "Order", "Tidy", "Write up", "Check", "Sort"]
        let nouns = ["the budget", "the trip", "the report", "the shelves", "the invoice", "the slides", "the garden", "the car", "the notes", "the lease"]
        let priorities: [TaskPriority?] = [nil, .low, .medium, .high, .urgent, nil]
        for index in 0..<count {
            let task = makeTask(
                "bulk-\(index)", "\(verbs[index % verbs.count]) \(nouns[(index / verbs.count) % nouns.count]) \(index)",
                project: index.isMultiple(of: 8) ? nil : projects[index % projects.count], in: context
            )
            task.priority = priorities[index % priorities.count]
            if index.isMultiple(of: 5) { task.status = .done } else if index.isMultiple(of: 6) { task.status = .inProgress }
            switch index % 4 {
            case 0: task.scheduledDay = day(index % 21 - 14)
            case 1: task.deadline = day(index % 60 - 7)
            case 2:
                task.scheduledDay = day(index % 10)
                task.deadline = day(index % 10 + 5)
            default: break
            }
            if index.isMultiple(of: 10) {
                for step in 0..<2 {
                    let subtask = makeTask("bulk-\(index)-step-\(step)", "Step \(step + 1)", project: task.project, in: context)
                    subtask.parentId = task.externalTaskID
                    subtask.parent = task
                    subtask.sortIndex = step
                    task.subtasks.append(subtask)
                }
            }
        }
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
