import Foundation

struct FinallyServerTask: Equatable, Sendable {
    let revision: Int64
    let id: String
    let projectID: Int64
    let title: String
    let isCompleted: Bool
    let plannedDay: Date?
    let deadline: Date?
    let priority: TaskPriority?

    init(
        id: String,
        projectID: Int64,
        title: String,
        isCompleted: Bool,
        plannedDay: Date? = nil,
        deadline: Date? = nil,
        priority: TaskPriority? = nil,
        revision: Int64 = 0
    ) {
        self.revision = revision
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isCompleted = isCompleted
        self.plannedDay = plannedDay
        self.deadline = deadline
        self.priority = priority
    }
}

struct FinallyServerTaskMutation: Codable, Equatable, Sendable {
    var baseRevision: Int64 = 0
    var changedFields: Set<String>?
    let title: String
    let isCompleted: Bool
    let plannedDay: Date?
    let deadline: Date?
    let priority: TaskPriority?

    init(
        title: String,
        isCompleted: Bool = false,
        plannedDay: Date? = nil,
        deadline: Date? = nil,
        priority: TaskPriority? = nil
    ) {
        self.title = title
        self.isCompleted = isCompleted
        self.plannedDay = plannedDay
        self.deadline = deadline
        self.priority = priority
    }
}

struct FinallyServerDailyFocusPick: Codable, Equatable, Sendable {
    let provider: String
    let workspaceID: String
    let externalTaskID: String

    enum CodingKeys: String, CodingKey {
        case provider
        case workspaceID = "workspace_id"
        case externalTaskID = "external_task_id"
    }
}

struct FinallyServerDailyFocus: Codable, Equatable, Sendable {
    let projectID: Int64
    let day: String
    let picks: [FinallyServerDailyFocusPick]
    let isConfirmed: Bool
    let focusLimit: Int

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case day
        case picks
        case isConfirmed = "confirmed"
        case focusLimit = "focus_limit"
    }
}

struct FinallyServerDailyFocusMutation: Equatable, Sendable {
    let picks: [FinallyServerDailyFocusPick]
    let isConfirmed: Bool
    let focusLimit: Int
}

struct FinallyServerProject: Identifiable, Hashable, Sendable, Decodable {
    let id: Int64
    let title: String
}

enum FinallyServerClientError: Error, LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case invalidCredentials
    case unauthorized
    case forbidden
    case notFound
    case duplicateLocalTaskIdentity(String)
    case conflict(current: FinallyServerTask, fields: [String])
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Enter a valid HTTPS server address and select a workspace."
        case .invalidResponse:
            return "Finally Server returned an unreadable response."
        case .invalidCredentials:
            return "Check your username and password, then try again."
        case .unauthorized:
            return "Your Finally Server connection has expired. Reconnect it in Settings."
        case .forbidden:
            return "This account cannot edit the selected Finally Server project."
        case .notFound:
            return "This server task is unavailable. Review your saved phone edit."
        case let .duplicateLocalTaskIdentity(taskID):
            return "Finally found multiple local tasks for server task \(taskID). Remove the duplicate and sync again."
        case .conflict:
            return "Review the task conflict. Your phone edits remain saved."
        case .serverUnavailable:
            return "Finally Server is unavailable. Your changes remain on this device."
        }
    }
}

protocol FinallyServerAPIClient: AnyObject {
    func login(username: String, password: String) async throws -> String
    func listProjects() async throws -> [FinallyServerProject]
    func listTasks(projectID: Int64) async throws -> [FinallyServerTask]
    func createTask(projectID: Int64, mutation: FinallyServerTaskMutation) async throws -> FinallyServerTask
    func readTask(id: String) async throws -> FinallyServerTask
    func updateTask(id: String, mutation: FinallyServerTaskMutation) async throws -> FinallyServerTask
    func completeTask(id: String, revision: Int64) async throws -> FinallyServerTask
    func deleteTask(id: String, revision: Int64) async throws
    /// The Daily Focus stored for one project and day, or nil when the server holds none.
    func readDailyFocus(projectID: Int64, day: String) async throws -> FinallyServerDailyFocus?
    func writeDailyFocus(
        projectID: Int64,
        day: String,
        mutation: FinallyServerDailyFocusMutation
    ) async throws -> FinallyServerDailyFocus
}

extension FinallyServerAPIClient {
    func createTask(projectID: Int64, title: String) async throws -> FinallyServerTask {
        try await createTask(projectID: projectID, mutation: FinallyServerTaskMutation(title: title))
    }

    func updateTask(id: String, title: String, isCompleted: Bool, revision: Int64) async throws -> FinallyServerTask {
        var mutation = FinallyServerTaskMutation(title: title, isCompleted: isCompleted)
        mutation.baseRevision = revision
        mutation.changedFields = ["title", "done"]
        return try await updateTask(id: id, mutation: mutation)
    }

}

final class URLSessionFinallyServerAPIClient: FinallyServerAPIClient {
    private struct LoginResponse: Decodable { let token: String }
    private struct PaginatedTasksResponse: Decodable {
        let items: [RemoteTask]
        let page: Int
        let totalPages: Int

        enum CodingKeys: String, CodingKey {
            case items, page
            case totalPages = "total_pages"
        }
    }

    private struct RemoteTask: Decodable {
        let id: Int64
        let projectID: Int64
        let title: String
        let done: Bool
        let revision: Int64
        let startDate: String?
        let deadline: String?
        let priority: Int64?

        enum CodingKeys: String, CodingKey {
            case id, title, done, revision
            case projectID = "project_id"
            case startDate = "start_date"
            case deadline = "due_date"
            case priority
        }

        var task: FinallyServerTask {
            FinallyServerTask(
                id: String(id),
                projectID: projectID,
                title: title,
                isCompleted: done,
                plannedDay: Self.parseDate(startDate),
                deadline: Self.parseDate(deadline),
                priority: Self.taskPriority(priority ?? 0),
                revision: revision
            )
        }

        private static func parseDate(_ value: String?) -> Date? {
            guard let value,
                  !value.hasPrefix("0001-01-01"),
                  let date = ISO8601DateFormatter().date(from: value) else { return nil }
            return date
        }

        private static func taskPriority(_ value: Int64) -> TaskPriority? {
            switch value {
            case 4: .urgent
            case 3: .high
            case 2: .medium
            case 1: .low
            default: nil
            }
        }
    }

    private let baseURL: URL
    private let token: String?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func login(username: String, password: String) async throws -> String {
        let response: LoginResponse = try await send(
            path: "login",
            method: "POST",
            body: ["username": username, "password": password],
            authenticated: false
        )
        return response.token
    }

    func listProjects() async throws -> [FinallyServerProject] {
        try await send(path: "projects", method: "GET")
    }

    func listTasks(projectID: Int64) async throws -> [FinallyServerTask] {
        var page = 1
        var tasks: [FinallyServerTask] = []
        repeat {
            let response: PaginatedTasksResponse = try await send(
                path: "projects/\(projectID)/tasks",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "1000"),
                ]
            )
            guard response.page == page, (0...10_000).contains(response.totalPages) else {
                throw FinallyServerClientError.invalidResponse
            }
            tasks.append(contentsOf: response.items.map(\.task))
            page += 1
            if page > response.totalPages { break }
        } while true
        return tasks
    }

    func createTask(projectID: Int64, mutation: FinallyServerTaskMutation) async throws -> FinallyServerTask {
        let response: RemoteTask = try await send(
            path: "projects/\(projectID)/tasks",
            method: "POST",
            body: taskBody(mutation)
        )
        return response.task
    }

    func readTask(id: String) async throws -> FinallyServerTask {
        let response: RemoteTask = try await send(path: "tasks/\(id)", method: "GET")
        return response.task
    }

    func updateTask(id: String, mutation: FinallyServerTaskMutation) async throws -> FinallyServerTask {
        let response: RemoteTask = try await send(
            path: "tasks/\(id)",
            method: "PUT",
            body: ["base_revision": mutation.baseRevision, "client": "phone", "fields": EncodableDictionary(taskBody(mutation).filter { mutation.changedFields?.contains($0.key) ?? true })]
        )
        return response.task
    }

    func completeTask(id: String, revision: Int64) async throws -> FinallyServerTask {
        let response: RemoteTask = try await send(path: "tasks/\(id)/complete", method: "POST", queryItems: [URLQueryItem(name: "base_revision", value: String(revision)), URLQueryItem(name: "client", value: "phone")])
        return response.task
    }

    func deleteTask(id: String, revision: Int64) async throws {
        let _: EmptyResponse = try await send(path: "tasks/\(id)", method: "DELETE", queryItems: [URLQueryItem(name: "base_revision", value: String(revision)), URLQueryItem(name: "client", value: "phone")])
    }

    func readDailyFocus(projectID: Int64, day: String) async throws -> FinallyServerDailyFocus? {
        do {
            return try await send(path: "projects/\(projectID)/daily-focus/\(day)", method: "GET")
        } catch FinallyServerClientError.notFound {
            return nil
        }
    }

    func writeDailyFocus(
        projectID: Int64,
        day: String,
        mutation: FinallyServerDailyFocusMutation
    ) async throws -> FinallyServerDailyFocus {
        try await send(
            path: "projects/\(projectID)/daily-focus/\(day)",
            method: "PUT",
            body: [
                "picks": mutation.picks,
                "confirmed": mutation.isConfirmed,
                "focus_limit": mutation.focusLimit,
            ]
        )
    }

    private func taskBody(_ mutation: FinallyServerTaskMutation) -> [String: any Encodable] {
        let formatter = ISO8601DateFormatter()
        return [
            "title": mutation.title,
            "done": mutation.isCompleted,
            "start_date": mutation.plannedDay.map { formatter.string(from: $0) } as String?,
            "due_date": mutation.deadline.map { formatter.string(from: $0) } as String?,
            "priority": providerPriority(mutation.priority),
        ]
    }

    private func providerPriority(_ priority: TaskPriority?) -> Int64 {
        switch priority {
        case .urgent: 4
        case .high: 3
        case .medium: 2
        case .low: 1
        case nil: 0
        }
    }

    private struct EmptyResponse: Decodable {}
    private struct ConflictResponse: Decodable { let current: RemoteTask; let conflicting_fields: [String] }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: [String: any Encodable]? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else {
            throw FinallyServerClientError.invalidConfiguration
        }
        let apiRoot = baseURL.appending(path: "api/v2/finally")
        let endpoint = apiRoot.appending(path: path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw FinallyServerClientError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token else { throw FinallyServerClientError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(EncodableDictionary(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FinallyServerClientError.serverUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw FinallyServerClientError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            if Response.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! Response
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw FinallyServerClientError.invalidResponse
            }
        case 401: throw FinallyServerClientError.unauthorized
        case 403 where !authenticated: throw FinallyServerClientError.invalidCredentials
        case 403: throw FinallyServerClientError.forbidden
        case 404: throw FinallyServerClientError.notFound
        case 409:
            guard let conflict = try? decoder.decode(ConflictResponse.self, from: data) else { throw FinallyServerClientError.invalidResponse }
            throw FinallyServerClientError.conflict(current: conflict.current.task, fields: conflict.conflicting_fields)
        default: throw FinallyServerClientError.serverUnavailable
        }
    }
}

private struct EncodableDictionary: Encodable {
    let values: [String: any Encodable]

    init(_ values: [String: any Encodable]) {
        self.values = values
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            try value.encode(to: container.superEncoder(forKey: DynamicCodingKey(stringValue: key)!))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
    }
}
