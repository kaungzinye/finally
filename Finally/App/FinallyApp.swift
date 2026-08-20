import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

@main
struct FinallyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = NavigationRouter()
    @State private var taskProvider = TaskProviderCoordinator()
    @State private var authService = NotionAuthService()
    @State private var networkService = NetworkService()
    @State private var hasSession = false
    @State private var needsDatabaseSetup = false
    @State private var isLoading = true
    @State private var notificationDelegate: NotificationDelegate?
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0 // 0=system, 1=light, 2=dark

    var body: some Scene {
        WindowGroup {
            Group {
                if isDeadlineDemoMode {
                    DeadlineDemoView()
                } else if isLoading {
                    ProgressView("Loading...")
                } else if !hasSession {
                    NotionConnectView(onConnected: {
                        needsDatabaseSetup = true
                        hasSession = true
                    })
                } else if needsDatabaseSetup {
                    DatabasePickerView(onComplete: {
                        needsDatabaseSetup = false
                        Task { await triggerSync() }
                    })
                } else {
                    ContentView()
                }
            }
            .environment(router)
            .environment(taskProvider)
            .environment(networkService)
            .tint(Color(.label))
            .preferredColorScheme(colorScheme)
            .onOpenURL { url in
                router.handleURL(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await runIncrementalSyncIfPossible() }
                }
            }
            .onChange(of: router.pendingOAuthCode) { _, code in
                guard let code else { return }
                Task { await handleOAuthCallback(code: code) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notionSessionExpired)) { _ in
                handleSessionExpired()
            }
            .onReceive(NotificationCenter.default.publisher(for: .notionDatabasesReset)) { _ in
                needsDatabaseSetup = true
            }
            .task {
                await checkSession()
                await startForegroundSyncLoop()
            }
        }
        .modelContainer(appContainer)
    }

    // MARK: - Appearance

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private var isDeadlineDemoMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-deadline-demo")
#else
        false
#endif
    }

    // MARK: - Session Check

    @MainActor
    private func checkSession() async {
        // Set up notification delegate
        let delegate = NotificationDelegate(router: router)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        let token = KeychainHelper.readNotionToken()
        let serverCredentials = KeychainFinallyServerCredentialStore()
        let context = ModelContext(appContainer)
        let sessions = (try? context.fetch(FetchDescriptor<UserSession>())) ?? []
        let usableSessions = sessions.filter { session in
            switch session.providerIdentity {
            case .notion: token != nil
            case .finallyServer: serverCredentials.token(workspaceID: session.workspaceId) != nil
            default: false
            }
        }
        hasSession = !usableSessions.isEmpty
        if usableSessions.selectedProviderWorkspace == nil, let first = usableSessions.first {
            sessions.forEach { $0.isSelected = $0.id == first.id }
            try? context.save()
        }
        let selectedSession = usableSessions.selectedProviderWorkspace ?? usableSessions.first

        print("[FinallyApp] checkSession: token=\(token != nil), sessions=\(sessions.count), hasSession=\(hasSession)")

        // Check if database IDs are configured
        if let session = selectedSession,
           session.providerIdentity == .notion,
           session.tasksDatabaseId.isEmpty {
            needsDatabaseSetup = true
            print("[FinallyApp] needsDatabaseSetup=true (tasksDatabaseId is empty)")
        }

        print("[FinallyApp] Final state: isLoading=false, hasSession=\(hasSession), needsDatabaseSetup=\(needsDatabaseSetup)")
        print("[FinallyApp] Will show: \(!hasSession ? "NotionConnectView" : needsDatabaseSetup ? "DatabasePickerView" : "ContentView")")

        isLoading = false

        // Trigger sync on launch if we have a session with databases configured
        if hasSession && !needsDatabaseSetup, let selectedSession {
            try? await taskProvider.synchronize(.launch, workspace: selectedSession, store: context)
        }
    }

    @MainActor
    private func handleOAuthCallback(code: String) async {
        let context = ModelContext(appContainer)
        let success = await authService.completeOAuth(withCode: code, modelContext: context)
        if success {
            hasSession = true
            if let session = try? context.selectedProviderWorkspace() {
                try? await taskProvider.synchronize(.launch, workspace: session, store: context)
            }
        }
        router.pendingOAuthCode = nil
    }

    @MainActor
    private func handleSessionExpired() {
        let context = ModelContext(appContainer)
        if let sessions = try? context.fetch(FetchDescriptor<UserSession>()) {
            for session in sessions where session.providerIdentity == .notion {
                context.delete(session)
            }
            if let firstRemaining = sessions.first(where: { $0.providerIdentity != .notion }) {
                firstRemaining.isSelected = true
            }
            try? context.save()
        }
        let remaining = (try? context.fetchCount(FetchDescriptor<UserSession>())) ?? 0
        hasSession = remaining > 0
        router.showReauthPrompt = true
    }

    @MainActor
    private func triggerSync() async {
        let context = ModelContext(appContainer)
        guard let session = try? context.selectedProviderWorkspace() else { return }
        try? await taskProvider.synchronize(.launch, workspace: session, store: context)
    }

    private func runIncrementalSyncIfPossible() async {
        guard hasSession else { return }
        let context = ModelContext(appContainer)
        guard let session = try? context.selectedProviderWorkspace() else { return }
        try? await taskProvider.synchronize(.incremental, workspace: session, store: context)
    }

    private func startForegroundSyncLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(AppConstants.syncIntervalSeconds))
            if scenePhase == .active {
                await runIncrementalSyncIfPossible()
            }
        }
    }

    // MARK: - Model Container

    private var appContainer: ModelContainer {
        do {
            return try ModelContainer.shared()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

#if DEBUG
private struct DeadlineDemoView: View {
    @State private var task = DeadlineDemoFixture.makeTask()

    var body: some View {
        TaskDetailView(task: task)
    }
}
#endif
