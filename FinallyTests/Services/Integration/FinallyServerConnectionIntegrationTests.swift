import SwiftData
import XCTest
@testable import Finally

@MainActor
final class FinallyServerConnectionIntegrationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testConnectingServerStoresCredentialForOnlyItsWorkspaceAndSelectsIt() async throws {
        let api = MockFinallyServerAPIClient()
        let credentials = InMemoryCredentialStore()
        let context = try makeInMemoryContext()
        let notion = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        context.insert(notion)

        let accounts = FinallyServerAccountService(api: api, credentials: credentials)
        let authenticated = try await accounts.authenticate(
            baseURL: URL(string: "https://tasks.example.com")!,
            username: "kaung",
            password: "secret"
        )
        let server = try accounts.connect(
            name: "Personal Server",
            baseURL: URL(string: "https://tasks.example.com")!,
            project: try XCTUnwrap(authenticated.projects.first),
            account: authenticated,
            store: context
        )

        XCTAssertEqual(server.providerIdentity, .finallyServer)
        XCTAssertEqual(server.serverBaseURL, "https://tasks.example.com")
        XCTAssertEqual(server.serverProjectID, 42)
        XCTAssertEqual(credentials.token(workspaceID: server.workspaceId), "server-token")
        XCTAssertNil(credentials.token(workspaceID: notion.workspaceId))
        XCTAssertTrue(server.isSelected)
        XCTAssertFalse(notion.isSelected)
        XCTAssertEqual(authenticated.projects, [FinallyServerProject(id: 42, title: "Personal")])
        let storedProjects = try context.fetch(FetchDescriptor<ProjectItem>())
        XCTAssertEqual(storedProjects.map(\.title), ["Personal"])
        XCTAssertEqual(storedProjects.map(\.providerWorkspaceId), [server.workspaceId])
    }

    func testRemovingServerAccountPreservesNotionWorkspaceAndCredential() async throws {
        let api = MockFinallyServerAPIClient()
        let credentials = InMemoryCredentialStore()
        let context = try makeInMemoryContext()
        let notion = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        context.insert(notion)
        try credentials.saveToken("notion-token", workspaceID: notion.workspaceId)
        let accounts = FinallyServerAccountService(api: api, credentials: credentials)
        let authenticated = try await accounts.authenticate(
            baseURL: URL(string: "https://tasks.example.com")!,
            username: "kaung",
            password: "secret"
        )
        let server = try accounts.connect(
            name: "Personal Server",
            baseURL: URL(string: "https://tasks.example.com")!,
            project: try XCTUnwrap(authenticated.projects.first),
            account: authenticated,
            store: context
        )
        let notionTask = TaskItem(externalTaskID: "notion-task", title: "Shared task")
        notionTask.providerWorkspaceId = notion.workspaceId
        context.insert(notionTask)
        let serverTask = TaskItem(externalTaskID: "1", title: "Private task")
        serverTask.providerWorkspaceId = server.workspaceId
        let notionProject = ProjectItem(externalProjectID: "notion-project", title: "Shared project")
        notionProject.providerWorkspaceId = notion.workspaceId
        let serverProject = ProjectItem(externalProjectID: "server-project", title: "Private project")
        serverProject.providerWorkspaceId = server.workspaceId
        context.insert(serverTask)
        context.insert(notionProject)
        context.insert(serverProject)
        try context.save()

        try accounts.remove(server, store: context)

        let sessions = try context.fetch(FetchDescriptor<UserSession>())
        XCTAssertEqual(sessions.map(\.workspaceId), [notion.workspaceId])
        XCTAssertEqual(credentials.token(workspaceID: notion.workspaceId), "notion-token")
        XCTAssertNil(credentials.token(workspaceID: server.workspaceId))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Shared task"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProjectItem>()).map(\.title), ["Shared project"])
    }

    func testFailedConnectionDoesNotPersistAccountOrCredential() async throws {
        let api = MockFinallyServerAPIClient()
        api.error = FinallyServerClientError.unauthorized
        let credentials = InMemoryCredentialStore()
        let context = try makeInMemoryContext()
        let accounts = FinallyServerAccountService(api: api, credentials: credentials)

        do {
            _ = try await accounts.authenticate(
                baseURL: URL(string: "https://tasks.example.com")!,
                username: "kaung",
                password: "wrong"
            )
            XCTFail("Expected authentication failure")
        } catch FinallyServerClientError.unauthorized {
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSession>()), 0)
            XCTAssertTrue(credentials.credentials.isEmpty)
        }
    }

    func testInsecureServerAddressIsRejectedBeforeCredentialsAreSent() async throws {
        let api = MockFinallyServerAPIClient()
        let accounts = FinallyServerAccountService(api: api, credentials: InMemoryCredentialStore())

        do {
            _ = try await accounts.authenticate(
                baseURL: URL(string: "http://tasks.example.com")!,
                username: "kaung",
                password: "secret"
            )
            XCTFail("Expected insecure transport rejection")
        } catch FinallyServerClientError.invalidConfiguration {
            XCTAssertEqual(api.loginRequests, 0)
        }
    }

    func testSwitchingWorkspaceKeepsProviderTasksSeparate() throws {
        let context = try makeInMemoryContext()
        let notion = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        notion.providerIdentity = .notion
        notion.isSelected = false
        let server = makeServerWorkspace()
        server.isSelected = true
        context.insert(notion)
        context.insert(server)
        let notionTask = TaskItem(externalTaskID: "1", title: "Notion task")
        notionTask.providerWorkspaceId = notion.workspaceId
        let serverTask = TaskItem(externalTaskID: "1", title: "Server task")
        serverTask.providerWorkspaceId = server.workspaceId
        let notionProject = ProjectItem(externalProjectID: "notion-project", title: "Shared project")
        notionProject.providerWorkspaceId = notion.workspaceId
        let serverProject = ProjectItem(externalProjectID: "server-project", title: "Private project")
        serverProject.providerWorkspaceId = server.workspaceId
        context.insert(notionTask)
        context.insert(serverTask)
        context.insert(notionProject)
        context.insert(serverProject)
        try context.save()

        XCTAssertEqual([notionTask, serverTask].scoped(to: server).map(\.title), ["Server task"])
        XCTAssertEqual([notionProject, serverProject].scoped(to: server).map(\.title), ["Private project"])

        notion.isSelected = true
        server.isSelected = false
        try context.save()
        XCTAssertEqual([notionTask, serverTask].scoped(to: notion).map(\.title), ["Notion task"])
        XCTAssertEqual([notionProject, serverProject].scoped(to: notion).map(\.title), ["Shared project"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
    }

    func testPresentationSummariesUseSelectedWorkspaceAcrossProviders() throws {
        let notion = UserSession(workspaceId: "notion-workspace", workspaceName: "Shared")
        notion.providerIdentity = .notion
        let server = makeServerWorkspace()
        server.isSelected = true
        notion.isSelected = false
        let notionTask = TaskItem(externalTaskID: "same-id", title: "Notion task")
        notionTask.providerWorkspaceId = notion.workspaceId
        let serverTask = TaskItem(externalTaskID: "same-id", title: "Server task")
        serverTask.providerWorkspaceId = server.workspaceId

        let summaries = TaskPresentationQuery.summaries(
            from: [notionTask, serverTask],
            workspace: server
        )

        XCTAssertEqual(summaries.map(\.title), ["Server task"])
        XCTAssertEqual(summaries.map(\.id), ["server-workspace:same-id"])
    }

    func testPresentationSummariesRetainTasksForUnavailableProvider() {
        let unavailable = UserSession(workspaceId: "offline-workspace", workspaceName: "Offline")
        unavailable.providerRaw = "temporarily-unavailable"
        let task = TaskItem(externalTaskID: "task-1", title: "Available offline")
        task.providerWorkspaceId = unavailable.workspaceId

        let summaries = TaskPresentationQuery.summaries(from: [task], workspace: unavailable)

        XCTAssertEqual(summaries.map(\.title), ["Available offline"])
    }

    func testFinallyServerAdapterRoundTripsEditCompleteReopenAndDelete() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        context.insert(workspace)
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Plan tomorrow")
        task.providerWorkspaceId = workspace.workspaceId
        task.isDirty = true
        context.insert(task)
        let adapter = FinallyServerTaskProviderAdapter(api: api)

        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(task.externalTaskID, "1")
        XCTAssertFalse(task.isDirty)
        XCTAssertEqual(api.tasks["1"]?.title, "Plan tomorrow")

        task.title = "Plan focused tomorrow"
        task.isDirty = true
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertEqual(api.tasks["1"]?.title, "Plan focused tomorrow")

        task.complete()
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertTrue(api.tasks["1"]?.isCompleted == true)
        XCTAssertFalse(task.isDirty)

        task.status = .notStarted
        task.isDirty = true
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertFalse(api.tasks["1"]?.isCompleted == true)

        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Remote title", isCompleted: false)
        try await adapter.synchronize(.incremental, workspace: workspace, store: context)
        XCTAssertEqual(task.title, "Remote title")

        task.isDeleted = true
        task.isDirty = true
        try await adapter.synchronize(.push, workspace: workspace, store: context)
        XCTAssertNil(api.tasks["1"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    func testFinallyServerPushCompletesTaskFinishedBeforeFirstSync() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Already finished")
        task.providerWorkspaceId = workspace.workspaceId
        task.status = .done
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.push, workspace: workspace, store: context)

        XCTAssertEqual(task.externalTaskID, "1")
        XCTAssertEqual(api.taskOperations, ["complete"])
        XCTAssertTrue(api.tasks["1"]?.isCompleted == true)
        XCTAssertEqual(task.status, .done)
        XCTAssertFalse(task.isDirty)
    }

    func testFinallyServerRetriesCompletionWithoutCreatingSecondRemoteTask() async throws {
        let api = MockFinallyServerAPIClient()
        api.completeError = FinallyServerClientError.serverUnavailable
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: UUID().uuidString, title: "Retry completion")
        task.providerWorkspaceId = workspace.workspaceId
        task.status = .done
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)

        do {
            try await FinallyServerTaskProviderAdapter(api: api)
                .synchronize(.push, workspace: workspace, store: context)
            XCTFail("Expected completion failure")
        } catch FinallyServerClientError.serverUnavailable {
            XCTAssertEqual(task.externalTaskID, "1")
            XCTAssertNotNil(task.lastSyncedAt)
            XCTAssertTrue(task.isDirty)
            XCTAssertEqual(api.tasks.count, 1)
        }

        api.completeError = nil
        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.push, workspace: workspace, store: context)

        XCTAssertEqual(api.tasks.count, 1)
        XCTAssertTrue(api.tasks["1"]?.isCompleted == true)
        XCTAssertFalse(task.isDirty)
    }

    func testFinallyServerLaunchDiscoversRemoteTasksInSelectedProject() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["77"] = FinallyServerTask(
            id: "77",
            projectID: 42,
            title: "Found on server",
            isCompleted: false
        )
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let project = ProjectItem(externalProjectID: "42", title: "Personal")
        project.providerWorkspaceId = workspace.workspaceId
        context.insert(workspace)
        context.insert(project)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.launch, workspace: workspace, store: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(task.externalTaskID, "77")
        XCTAssertEqual(task.providerWorkspaceId, workspace.workspaceId)
        XCTAssertEqual(task.title, "Found on server")
        XCTAssertEqual(task.project?.externalProjectID, "42")
        XCTAssertFalse(task.isDirty)
        XCTAssertNotNil(task.lastSyncedAt)
    }

    func testFinallyServerDiscoveryPreservesDirtyTaskAndOtherWorkspaceIdentity() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(
            id: "1",
            projectID: 42,
            title: "Remote title",
            isCompleted: false
        )
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let dirtyTask = TaskItem(externalTaskID: "1", title: "Phone edit")
        dirtyTask.providerWorkspaceId = workspace.workspaceId
        dirtyTask.lastSyncedAt = Date()
        dirtyTask.isDirty = true
        let notionTask = TaskItem(externalTaskID: "1", title: "Notion copy")
        notionTask.providerWorkspaceId = "notion-workspace"
        context.insert(workspace)
        context.insert(dirtyTask)
        context.insert(notionTask)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.full, workspace: workspace, store: context)

        XCTAssertEqual(dirtyTask.title, "Phone edit")
        XCTAssertTrue(dirtyTask.isDirty)
        XCTAssertEqual(notionTask.title, "Notion copy")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
    }

    func testFinallyServerDiscoveryRemovesCleanTaskDeletedRemotely() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let staleTask = TaskItem(externalTaskID: "404", title: "Deleted remotely")
        staleTask.providerWorkspaceId = workspace.workspaceId
        staleTask.lastSyncedAt = Date()
        context.insert(workspace)
        context.insert(staleTask)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.full, workspace: workspace, store: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    func testFinallyServerDiscoveryReportsDuplicateLocalTaskIdentity() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let first = TaskItem(externalTaskID: "1", title: "First copy")
        first.providerWorkspaceId = workspace.workspaceId
        let second = TaskItem(externalTaskID: "1", title: "Second copy")
        second.providerWorkspaceId = workspace.workspaceId
        context.insert(workspace)
        context.insert(first)
        context.insert(second)

        do {
            try await FinallyServerTaskProviderAdapter(api: api)
                .synchronize(.full, workspace: workspace, store: context)
            XCTFail("Expected duplicate identity failure")
        } catch let FinallyServerClientError.duplicateLocalTaskIdentity(taskID) {
            XCTAssertEqual(taskID, "1")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
        }
    }

    func testFinallyServerFailureKeepsLocalEditRecoverable() async throws {
        let api = MockFinallyServerAPIClient()
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        context.insert(workspace)
        let task = TaskItem(externalTaskID: "1", title: "Edit survives")
        task.providerWorkspaceId = workspace.workspaceId
        task.lastSyncedAt = Date()
        task.isDirty = true
        context.insert(task)
        api.error = FinallyServerClientError.serverUnavailable
        let adapter = FinallyServerTaskProviderAdapter(api: api)

        do {
            try await adapter.synchronize(.push, workspace: workspace, store: context)
            XCTFail("Expected server unavailability")
        } catch FinallyServerClientError.serverUnavailable {
            XCTAssertTrue(task.isDirty)
            XCTAssertEqual(task.title, "Edit survives")
        }
    }

    func testDirtyCompletedTaskPushesEditedTitleBeforeCompletion() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Old title", isCompleted: false)
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: "1", title: "Edited title")
        task.providerWorkspaceId = workspace.workspaceId
        task.lastSyncedAt = Date()
        task.status = .done
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)

        try await FinallyServerTaskProviderAdapter(api: api)
            .synchronize(.push, workspace: workspace, store: context)

        XCTAssertEqual(api.taskOperations, ["update", "complete"])
        XCTAssertEqual(api.tasks["1"]?.title, "Edited title")
        XCTAssertTrue(api.tasks["1"]?.isCompleted == true)
        XCTAssertEqual(task.title, "Edited title")
        XCTAssertEqual(task.status, .done)
        XCTAssertFalse(task.isDirty)
    }

    func testDirtyCompletedTaskKeepsLocalStateWhenEditFails() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Old title", isCompleted: false)
        api.updateError = FinallyServerClientError.serverUnavailable
        let (context, workspace, task) = try makeDirtyCompletedTask()

        do {
            try await FinallyServerTaskProviderAdapter(api: api)
                .synchronize(.push, workspace: workspace, store: context)
            XCTFail("Expected edit failure")
        } catch FinallyServerClientError.serverUnavailable {
            XCTAssertEqual(api.taskOperations, ["update"])
            XCTAssertEqual(task.title, "Edited title")
            XCTAssertEqual(task.status, .done)
            XCTAssertTrue(task.isDirty)
        }
    }

    func testDirtyCompletedTaskKeepsLocalStateWhenCompletionFails() async throws {
        let api = MockFinallyServerAPIClient()
        api.tasks["1"] = FinallyServerTask(id: "1", projectID: 42, title: "Old title", isCompleted: false)
        api.completeError = FinallyServerClientError.serverUnavailable
        let (context, workspace, task) = try makeDirtyCompletedTask()

        do {
            try await FinallyServerTaskProviderAdapter(api: api)
                .synchronize(.push, workspace: workspace, store: context)
            XCTFail("Expected completion failure")
        } catch FinallyServerClientError.serverUnavailable {
            XCTAssertEqual(api.taskOperations, ["update", "complete"])
            XCTAssertEqual(api.tasks["1"]?.title, "Edited title")
            XCTAssertFalse(api.tasks["1"]?.isCompleted == true)
            XCTAssertEqual(task.title, "Edited title")
            XCTAssertEqual(task.status, .done)
            XCTAssertTrue(task.isDirty)
        }
    }

    func testURLClientUsesVersionedAuthenticatedLifecycleContract() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requests: [URLRequest] = []
        MockURLProtocol.handler = { request in
            requests.append(request)
            let path = try XCTUnwrap(request.url?.path)
            let body: String
            let status: Int
            switch (request.httpMethod, path) {
            case ("POST", "/api/v2/finally/login"):
                body = #"{"token":"jwt-token"}"#
                status = 200
            case ("GET", "/api/v2/finally/projects"):
                body = #"[{"id":42,"title":"Personal"}]"#
                status = 200
            case ("POST", "/api/v2/finally/projects/42/tasks"):
                body = #"{"id":1,"project_id":42,"title":"Plan tomorrow","done":false}"#
                status = 201
            case ("GET", "/api/v2/finally/tasks/1"):
                body = #"{"id":1,"project_id":42,"title":"Plan tomorrow","done":false}"#
                status = 200
            case ("PUT", "/api/v2/finally/tasks/1"):
                body = #"{"id":1,"project_id":42,"title":"Plan focused tomorrow","done":false}"#
                status = 200
            case ("POST", "/api/v2/finally/tasks/1/complete"):
                body = #"{"id":1,"project_id":42,"title":"Plan focused tomorrow","done":true}"#
                status = 200
            case ("DELETE", "/api/v2/finally/tasks/1"):
                body = ""
                status = 204
            default:
                throw URLError(.unsupportedURL)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let baseURL = URL(string: "https://tasks.example.com")!
        let loginClient = URLSessionFinallyServerAPIClient(baseURL: baseURL, session: session)
        let token = try await loginClient.login(username: "kaung", password: "secret")
        let client = URLSessionFinallyServerAPIClient(baseURL: baseURL, token: token, session: session)
        let projects = try await client.listProjects()
        let created = try await client.createTask(projectID: 42, title: "Plan tomorrow")
        _ = try await client.readTask(id: created.id)
        _ = try await client.updateTask(id: created.id, title: "Plan focused tomorrow", isCompleted: false)
        _ = try await client.completeTask(id: created.id)
        try await client.deleteTask(id: created.id)

        XCTAssertEqual(token, "jwt-token")
        XCTAssertEqual(projects, [FinallyServerProject(id: 42, title: "Personal")])
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/api/v2/finally/login",
            "/api/v2/finally/projects",
            "/api/v2/finally/projects/42/tasks",
            "/api/v2/finally/tasks/1",
            "/api/v2/finally/tasks/1",
            "/api/v2/finally/tasks/1/complete",
            "/api/v2/finally/tasks/1",
        ])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(requests.dropFirst().allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token"
        })
    }

    func testURLClientListsEveryTaskPage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestedPages: [String?] = []
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/finally/projects/42/tasks")
            let page = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page" })?.value
            requestedPages.append(page)
            let body: String
            if page == "1" {
                body = #"{"items":[{"id":1,"project_id":42,"title":"First","done":false}],"total":2,"page":1,"per_page":1,"total_pages":2}"#
            } else {
                body = #"{"items":[{"id":2,"project_id":42,"title":"Second","done":true}],"total":2,"page":2,"per_page":1,"total_pages":2}"#
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        let client = URLSessionFinallyServerAPIClient(
            baseURL: URL(string: "https://tasks.example.com")!,
            token: "jwt-token",
            session: session
        )

        let tasks = try await client.listTasks(projectID: 42)

        XCTAssertEqual(requestedPages, ["1", "2"])
        XCTAssertEqual(tasks.map(\.id), ["1", "2"])
        XCTAssertEqual(tasks.map(\.title), ["First", "Second"])
    }

    func testLoginForbiddenResponseReportsInvalidCredentialsWithRetryGuidance() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/finally/login")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let client = URLSessionFinallyServerAPIClient(
            baseURL: URL(string: "https://tasks.example.com")!,
            session: session
        )

        do {
            _ = try await client.login(username: "kaung", password: "wrong")
            XCTFail("Expected invalid credentials")
        } catch FinallyServerClientError.invalidCredentials {
            XCTAssertEqual(
                FinallyServerClientError.invalidCredentials.localizedDescription,
                "Check your username and password, then try again."
            )
        }
    }

    func testAuthenticatedProjectForbiddenResponseKeepsPermissionGuidance() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/finally/projects")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let client = URLSessionFinallyServerAPIClient(
            baseURL: URL(string: "https://tasks.example.com")!,
            token: "jwt-token",
            session: session
        )

        do {
            _ = try await client.listProjects()
            XCTFail("Expected project permission failure")
        } catch FinallyServerClientError.forbidden {
            XCTAssertEqual(
                FinallyServerClientError.forbidden.localizedDescription,
                "This account cannot edit the selected Finally Server project."
            )
        }
    }

    private func makeServerWorkspace() -> UserSession {
        let workspace = UserSession(workspaceId: "server-workspace", workspaceName: "Personal Server")
        workspace.providerIdentity = .finallyServer
        workspace.serverBaseURL = "https://tasks.example.com"
        workspace.serverProjectID = 42
        return workspace
    }

    private func makeDirtyCompletedTask() throws -> (ModelContext, UserSession, TaskItem) {
        let context = try makeInMemoryContext()
        let workspace = makeServerWorkspace()
        let task = TaskItem(externalTaskID: "1", title: "Edited title")
        task.providerWorkspaceId = workspace.workspaceId
        task.lastSyncedAt = Date()
        task.status = .done
        task.isDirty = true
        context.insert(workspace)
        context.insert(task)
        return (context, workspace, task)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ProjectItem.self, UserSession.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
