import SwiftUI

struct ContentView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(NetworkService.self) private var networkService
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(DailyFocusService.self) private var dailyFocusService
    @Environment(\.modelContext) private var modelContext

    @State private var showCreator = false

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

                    BoardView()
                        .addTaskButton(isHidden: showCreator, action: openCreator)
                        .tabItem { Label("Board", systemImage: "rectangle.split.3x1") }
                        .tag(NavigationRouter.Tab.board)

                    BrowseProjectsView()
                        .addTaskButton(isHidden: showCreator, action: openCreator)
                        .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
                        .tag(NavigationRouter.Tab.browse)
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
