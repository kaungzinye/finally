import XCTest
import SwiftData
@testable import Finally

/// Base class for all E2E tests. Skips gracefully when credentials are absent.
class NotionE2ETestCase: XCTestCase {
    var api: NotionAPIService!
    var syncService: SyncService!
    var modelContext: ModelContext!
    var session: UserSession!

    /// Page IDs created during the test, archived in tearDown.
    var createdPageIds: [String] = []

    override func setUp() async throws {
        try XCTSkipIf(!E2EConfig.isConfigured, "Skipping E2E tests — NOTION_E2E_TOKEN and NOTION_E2E_TASKS_DB not set")

        api = NotionAPIService(token: E2EConfig.notionToken!)
        modelContext = try makeInMemoryContext()
        session = UserSession(workspaceId: "e2e-workspace", workspaceName: "E2E Workspace", providerIdentity: .notion)
        session.tasksDatabaseId = E2EConfig.tasksDatabaseId!
        if let projectsDb = E2EConfig.projectsDatabaseId {
            session.projectsDatabaseId = projectsDb
        }
        session.propertyMappings = PropertyMappings()
        modelContext.insert(session)
        try modelContext.save()

        syncService = SyncService(api: api)
    }

    override func tearDown() async throws {
        for pageId in createdPageIds {
            try? await api.archivePage(pageId: pageId)
        }
        createdPageIds = []
    }

    // MARK: - Helpers

    func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            TaskItem.self,
            ProjectItem.self,
            UserSession.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// Insert a local TaskItem, run pushDirtyChanges, and record the Notion page ID for cleanup.
    @discardableResult
    func pushLocalTask(title: String, configure: (TaskItem) -> Void = { _ in }) async throws -> TaskItem {
        let task = TaskItem(externalTaskID: "", title: title)
        task.isDirty = true
        configure(task)
        modelContext.insert(task)
        try modelContext.save()

        try await syncService.pushDirtyChanges(session: session, modelContext: modelContext)

        if !task.externalTaskID.isEmpty {
            createdPageIds.append(task.externalTaskID)
        }
        return task
    }

    /// Fetch a single TaskItem from the in-memory context matching a Notion page ID.
    func fetchTask(externalTaskID: String) throws -> TaskItem? {
        let id = externalTaskID
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.externalTaskID == id }
        )
        return try modelContext.fetch(descriptor).first
    }
}
