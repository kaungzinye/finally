import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

@main
struct FinallyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = NavigationRouter()
    @State private var syncService = SyncService()
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
                if isLoading {
                    ProgressView("Loading...")
                } else if !hasSession {
                    NotionConnectView(onConnected: {
                        needsDatabaseSetup = true
                        hasSession = true
                    })
                } else if needsDatabaseSetup {
                    DatabasePickerView(onComplete: {
                        needsDatabaseSetup = false
                    })
                } else {
                    ContentView()
                }
            }
            .environment(router)
            .environment(syncService)
            .environment(networkService)
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

    // MARK: - Session Check

    @MainActor
    private func checkSession() async {
        // Set up notification delegate
        let delegate = NotificationDelegate(router: router)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        let token = KeychainHelper.readNotionToken()
        let context = ModelContext(appContainer)
        let sessions = (try? context.fetch(FetchDescriptor<UserSession>())) ?? []
        let hasLocalSession = !sessions.isEmpty
        hasSession = token != nil && hasLocalSession

        // Check if database IDs are configured
        if let session = sessions.first, session.tasksDatabaseId.isEmpty {
            needsDatabaseSetup = true
        }

        isLoading = false

        // Trigger sync on launch if we have a session with databases configured
        if hasSession && !needsDatabaseSetup {
            await syncService.syncOnLaunch(modelContext: context)
        }
    }

    @MainActor
    private func handleOAuthCallback(code: String) async {
        let context = ModelContext(appContainer)
        let success = await authService.completeOAuth(withCode: code, modelContext: context)
        if success {
            hasSession = true
            await syncService.syncOnLaunch(modelContext: context)
        }
        router.pendingOAuthCode = nil
    }

    @MainActor
    private func handleSessionExpired() {
        let context = ModelContext(appContainer)
        if let sessions = try? context.fetch(FetchDescriptor<UserSession>()) {
            for session in sessions {
                context.delete(session)
            }
            try? context.save()
        }
        hasSession = false
        router.showReauthPrompt = true
    }

    private func runIncrementalSyncIfPossible() async {
        guard hasSession else { return }
        let context = ModelContext(appContainer)
        guard let session = ((try? context.fetch(FetchDescriptor<UserSession>())) ?? []).first else { return }
        try? await syncService.incrementalSync(session: session, modelContext: context)
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
