import Foundation
@testable import Finally

final class MockFinallyServerAPIClient: FinallyServerAPIClient {
    var loginToken = "server-token"
    var tasks: [String: FinallyServerTask] = [:]
    var nextTaskID = 1
    var error: Error?
    var updateError: Error?
    var completeError: Error?
    var projects = [FinallyServerProject(id: 42, title: "Personal")]
    private(set) var loginRequests = 0
    private(set) var taskOperations: [String] = []

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
            priority: mutation.priority
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
        let task = FinallyServerTask(
            id: current.id,
            projectID: current.projectID,
            title: mutation.title,
            isCompleted: mutation.isCompleted,
            plannedDay: mutation.plannedDay,
            deadline: mutation.deadline,
            priority: mutation.priority
        )
        tasks[id] = task
        return task
    }

    func completeTask(id: String) async throws -> FinallyServerTask {
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
            priority: current.priority
        )
        tasks[id] = task
        return task
    }

    func deleteTask(id: String) async throws {
        if let error { throw error }
        guard tasks.removeValue(forKey: id) != nil else { throw FinallyServerClientError.notFound }
    }
}

final class InMemoryCredentialStore: FinallyServerCredentialStore {
    private(set) var credentials: [String: String] = [:]

    func saveToken(_ token: String, workspaceID: String) throws {
        credentials[workspaceID] = token
    }

    func token(workspaceID: String) -> String? {
        credentials[workspaceID]
    }

    func deleteToken(workspaceID: String) {
        credentials.removeValue(forKey: workspaceID)
    }
}
