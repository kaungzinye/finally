import Foundation
@testable import Finally

final class MockFinallyServerAPIClient: FinallyServerAPIClient {
    var loginToken = "server-token"
    var tasks: [String: FinallyServerTask] = [:]
    var nextTaskID = 1
    var error: Error?
    var updateError: Error?
    var completeError: Error?
    var updateHook: (() async -> Void)?
    private(set) var mutations: [FinallyServerTaskMutation] = []
    var projects = [FinallyServerProject(id: 42, title: "Personal")]
    private(set) var loginRequests = 0
    private(set) var taskOperations: [String] = []
    var dailyFocus: [String: FinallyServerDailyFocus] = [:]
    private(set) var dailyFocusOperations: [String] = []
    var dailyFocusReadHook: (@MainActor () async -> Void)?
    var dailyFocusWriteHook: (@MainActor () async -> Void)?

    func login(username: String, password: String) async throws -> String {
        loginRequests += 1
        if let error { throw error }
        return loginToken
    }

    func listProjects() async throws -> [FinallyServerProject] {
        if let error { throw error }
        return projects
    }

    func listTasks(projectID: Int64) async throws -> [FinallyServerTask] {
        if let error { throw error }
        return tasks.values
            .filter { $0.projectID == projectID }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func createTask(projectID: Int64, mutation: FinallyServerTaskMutation) async throws -> FinallyServerTask {
        if let error { throw error }
        let task = FinallyServerTask(
            id: String(nextTaskID),
            projectID: projectID,
            title: mutation.title,
            isCompleted: mutation.isCompleted,
            plannedDay: mutation.plannedDay,
            deadline: mutation.deadline,
            priority: mutation.priority,
            deadlineHasTime: mutation.deadlineHasTime,
            reminders: mutation.reminders
        )
        nextTaskID += 1
        tasks[task.id] = task
        return task
    }

    func readTask(id: String) async throws -> FinallyServerTask {
        if let error { throw error }
        guard let task = tasks[id] else { throw FinallyServerClientError.notFound }
        return task
    }

    func updateTask(id: String, mutation: FinallyServerTaskMutation) async throws -> FinallyServerTask {
        taskOperations.append("update")
        if let updateError { throw updateError }
        if let error { throw error }
        guard let current = tasks[id] else { throw FinallyServerClientError.notFound }
        mutations.append(mutation)
        let fields = mutation.changedFields ?? ["title", "done", "start_date", "due_date", "priority", "deadline_has_time", "reminder_rules"]
        let task = FinallyServerTask(
            id: current.id, projectID: current.projectID,
            title: fields.contains("title") ? mutation.title : current.title,
            isCompleted: fields.contains("done") ? mutation.isCompleted : current.isCompleted,
            plannedDay: fields.contains("start_date") ? mutation.plannedDay : current.plannedDay,
            deadline: fields.contains("due_date") ? mutation.deadline : current.deadline,
            priority: fields.contains("priority") ? mutation.priority : current.priority,
            revision: current.revision + 1,
            deadlineHasTime: fields.contains("deadline_has_time") ? mutation.deadlineHasTime : current.deadlineHasTime,
            reminders: fields.contains("reminder_rules") ? mutation.reminders : current.reminders
        )
        await updateHook?()
        tasks[id] = task
        return task
    }

    func completeTask(id: String, revision: Int64) async throws -> FinallyServerTask {
        taskOperations.append("complete")
        if let completeError { throw completeError }
        if let error { throw error }
        guard let current = tasks[id] else { throw FinallyServerClientError.notFound }
        let task = FinallyServerTask(
            id: current.id,
            projectID: current.projectID,
            title: current.title,
            isCompleted: true,
            plannedDay: current.plannedDay,
            deadline: current.deadline,
            priority: current.priority,
            deadlineHasTime: current.deadlineHasTime,
            reminders: current.reminders
        )
        tasks[id] = task
        return task
    }

    func deleteTask(id: String, revision: Int64) async throws {
        if let error { throw error }
        guard tasks.removeValue(forKey: id) != nil else { throw FinallyServerClientError.notFound }
    }

    static func dailyFocusKey(projectID: Int64, day: String) -> String { "\(projectID)/\(day)" }

    func readDailyFocus(projectID: Int64, day: String) async throws -> FinallyServerDailyFocus? {
        dailyFocusOperations.append("read")
        if let error { throw error }
        let record = dailyFocus[Self.dailyFocusKey(projectID: projectID, day: day)]
        await dailyFocusReadHook?()
        return record
    }

    func writeDailyFocus(
        projectID: Int64,
        day: String,
        mutation: FinallyServerDailyFocusMutation
    ) async throws -> FinallyServerDailyFocus {
        dailyFocusOperations.append("write")
        if let error { throw error }
        let record = FinallyServerDailyFocus(
            projectID: projectID,
            day: day,
            picks: mutation.picks,
            isConfirmed: mutation.isConfirmed,
            focusLimit: mutation.focusLimit
        )
        dailyFocus[Self.dailyFocusKey(projectID: projectID, day: day)] = record
        await dailyFocusWriteHook?()
        return record
    }
}

final class InMemoryCredentialStore: FinallyServerCredentialStore {
    private(set) var credentials: [String: String] = [:]
    var saveError: Error?

    func saveToken(_ token: String, workspaceID: String) throws {
        if let saveError { throw saveError }
        credentials[workspaceID] = token
    }

    func token(workspaceID: String) -> String? {
        credentials[workspaceID]
    }

    func deleteToken(workspaceID: String) {
        credentials.removeValue(forKey: workspaceID)
    }
}
