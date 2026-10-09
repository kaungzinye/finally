import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

@main
struct FinallyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = NavigationRouter()
    @State private var taskProvider = TaskProviderCoordinator()
    @State private var dailyFocusService = DailyFocusService()
    @State private var authService = NotionAuthService()
    @State private var networkService = NetworkService()
    @State private var sessionRoute: ProviderSessionRoute = .connect
    @State private var isLoading = true
    @State private var notificationDelegate: NotificationDelegate?
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0 // 0=system, 1=light, 2=dark

    init() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [
            .font: UIFont.rounded(.largeTitle, weight: .bold),
            .foregroundColor: UIColor(Palette.ink),
        ]
        navigationBar.titleTextAttributes = [
            .font: UIFont.rounded(.headline, weight: .semibold),
            .foregroundColor: UIColor(Palette.ink),
        ]
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isDeadlineDemoMode {
                    DeadlineDemoView()
                } else if isDailyFocusDemoMode {
                    DailyFocusDemoView()
                } else if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Palette.paper.ignoresSafeArea())
                } else {
                    switch sessionRoute {
                    case .connect:
                        ProviderConnectView(onConnected: {
                            Task { await checkSession() }
                        })
                    case .databaseSetup:
                        DatabasePickerView(
                            onComplete: { Task { await checkSession() } },
                            onChooseProvider: { sessionRoute = .connect }
                        )
                    case .tasks:
                        ContentView()
                    }
                }
            }
            .environment(router)
            .environment(taskProvider)
            .environment(dailyFocusService)
            .environment(networkService)
            .environment(authService)
            .tint(Palette.ink)
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
                Task { await checkSession() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerWorkspaceChanged)) { _ in
                Task { await checkSession() }
            }
            .task {
                if isDeadlineDemoMode || isDailyFocusDemoMode { return }
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

    private var isDailyFocusDemoMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-daily-focus-demo")
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
        if usableSessions.selectedProviderWorkspace == nil, let first = usableSessions.first {
            sessions.forEach { $0.isSelected = $0.id == first.id }
            try? context.save()
        }
        let selectedSession = usableSessions.selectedProviderWorkspace ?? usableSessions.first

        sessionRoute = .resolve(selectedWorkspace: selectedSession)
        isLoading = false

        if sessionRoute == .tasks, let selectedSession {
            try? await taskProvider.synchronize(.launch, workspace: selectedSession, store: context)
        }
    }

    @MainActor
    private func handleOAuthCallback(code: String) async {
        router.pendingOAuthCode = nil
        guard !authService.isAuthenticating else { return }
        let context = ModelContext(appContainer)
        let success = await authService.completeOAuth(withCode: code, modelContext: context)
        if success {
            await checkSession()
        }
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
        Task { await checkSession() }
    }

    private func runIncrementalSyncIfPossible() async {
        guard sessionRoute == .tasks else { return }
        let context = ModelContext(appContainer)
        guard let session = try? context.selectedProviderWorkspace() else { return }
        try? await taskProvider.synchronize(.incremental, workspace: session, store: context)
    }

    private func startForegroundSyncLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(AppConstants.syncIntervalSeconds))
            } catch {
                return
            }
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

/// The Today tab over an in-memory store seeded with a Daily Focus that mixes providers and
/// carries one pick whose task is gone.
private struct DailyFocusDemoView: View {
    @State private var container = DailyFocusDemoFixture.makeContainer()

    var body: some View {
        ContentView()
            .modelContainer(container)
    }
}
#endif

private extension UIFont {
    /// SF Pro Rounded at a Dynamic Type text style.
    static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let weighted = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        let descriptor = weighted.withDesign(.rounded) ?? weighted
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
