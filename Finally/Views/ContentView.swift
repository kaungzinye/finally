import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(NetworkService.self) private var networkService
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(DailyFocusService.self) private var dailyFocusService
    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @State private var presentedTask: PresentedTask?
    private enum PresentedTask: Identifiable {
        case conflict(TaskItem), detail(TaskItem)
        var id: String { switch self { case .conflict(let task): "conflict-\(task.externalTaskID)"; case .detail(let task): "detail-\(task.externalTaskID)" } }
    }
    @State private var showCreator = false

    private var inboxCount: Int {
        TasksList(tasks: tasks, projects: [], workspace: sessions.selectedProviderWorkspace).inbox.count
    }

    var body: some View {
        @Bindable var router = router

        ZStack {
            VStack(spacing: 8) {
                callouts
                    .padding(.horizontal, 16)

                TabView(selection: $router.selectedTab) {
                    TodayView()
                        .addTaskButton(isHidden: showCreator, action: openCreator)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(NavigationRouter.Tab.today)

                    UpcomingView()
                        .addTaskButton(isHidden: showCreator, action: openCreator)
                        .tabItem { Label("Upcoming", systemImage: "calendar") }
                        .tag(NavigationRouter.Tab.upcoming)

                    TasksView()
                        .addTaskButton(isHidden: showCreator, action: openCreator)
                        .tabItem { Label("Tasks", systemImage: "checklist") }
                        .badge(inboxCount)
                        .tag(NavigationRouter.Tab.tasks)
                }
            }
            .background(Palette.paper.ignoresSafeArea())
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: networkService.isOnline)

            // Dismiss creator when tapping content area
            if showCreator {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showCreator = false }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showCreator {
                InlineTaskCreator(presetProject: router.creatorProject)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $presentedTask) { item in
            switch item { case .conflict(let task): TaskConflictReviewView(task: task); case .detail(let task): TaskDetailView(task: task) }
        }
        .onAppear { openNotificationTask() }
        .onChange(of: router.deepLinkTaskId) { _, _ in openNotificationTask() }
        .onChange(of: router.showNewTaskSheet) { _, show in
            guard show else { return }
            openCreator()
            router.showNewTaskSheet = false
        }
    }

    @ViewBuilder
    private var callouts: some View {
        if !networkService.isOnline {
            Callout(icon: "wifi.slash", message: "You're offline. Changes will sync when connection returns.")
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let conflict = tasks.first(where: { $0.providerWorkspaceId == sessions.selectedProviderWorkspace?.workspaceId && ($0.serverConflictJSON != nil || $0.serverTaskMissing) }) {
            Button("Review conflict: \(conflict.title)") { presentedTask = .conflict(conflict) }
                .buttonStyle(InkButtonStyle())
        }

        if let message = NotificationService.shared.authorizationMessage {
            Callout(message: message, onRetry: {
                if NotificationService.shared.authorizationNeedsSettings,
                   let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                else { Task { _ = await NotificationService.shared.requestPermission() } }
            })
        }
        if let message = NotificationService.shared.schedulingError {
            Callout(message: message, onRetry: { NotificationService.shared.rescheduleAllReminders(modelContext: modelContext) })
        }
        if NotificationService.shared.deferredCount > 0 {
            Callout(icon: "bell.badge", message: "\(NotificationService.shared.deferredCount) reminders stay queued. The nearest reminders are scheduled; opening the app refreshes the queue.")
        }

        if let message = taskProvider.lastError {
            Callout(
                message: message,
                onRetry: {
                    Task { await taskProvider.retryPendingChanges(store: modelContext) }
                },
                onDismiss: { taskProvider.clearError() }
            )
        }

        if let message = dailyFocusService.lastError {
            Callout(
                message: message,
                onRetry: { Task { await dailyFocusService.retryPendingChanges(store: modelContext) } },
                onDismiss: { dailyFocusService.clearError() }
            )
        }

        if let message = taskProvider.lastWarning {
            Callout(message: message, onDismiss: { taskProvider.clearWarning() })
        }
    }

    private func openNotificationTask() {
        guard let id = router.deepLinkTaskId,
              let task = tasks.first(where: { $0.externalTaskID == id && ($0.providerWorkspaceId ?? "local") == (router.deepLinkWorkspaceId ?? sessions.selectedProviderWorkspace?.workspaceId ?? "local") }) else { return }
        router.deepLinkTaskId = nil
        router.deepLinkWorkspaceId = nil
        if let workspace = task.providerWorkspaceId {
            sessions.forEach { $0.isSelected = $0.workspaceId == workspace }
            try? modelContext.save()
        }
        presentedTask = .detail(task)
    }

    private func openCreator() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showCreator = true }
    }
}

private extension View {
    /// The one floating add button, sitting above the tab bar in every tab.
    func addTaskButton(isHidden: Bool, action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            if !isHidden {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 56, height: 56)
                        .glassSurface(in: Circle())
                }
                .buttonStyle(.plain)
                .padding(16)
                .accessibilityLabel("Add a task")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }
}
