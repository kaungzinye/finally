import SwiftUI

struct ContentView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(NetworkService.self) private var networkService

    @State private var showCreator = false

    var body: some View {
        @Bindable var router = router

        ZStack {
            VStack(spacing: 0) {
                if !networkService.isOnline {
                    Text("You're offline. Changes will sync when connection returns.")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                TabView(selection: $router.selectedTab) {
                    InboxView()
                        .tabItem {
                            Label("Inbox", systemImage: "tray")
                        }
                        .tag(NavigationRouter.Tab.inbox)

                    TodayView()
                        .tabItem {
                            Label("Today", systemImage: "calendar")
                        }
                        .tag(NavigationRouter.Tab.today)

                    UpcomingView()
                        .tabItem {
                            Label("Upcoming", systemImage: "calendar.badge.clock")
                        }
                        .tag(NavigationRouter.Tab.upcoming)

                    SearchFilterView()
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .tag(NavigationRouter.Tab.search)

                    BrowseProjectsView()
                        .tabItem {
                            Label("Browse", systemImage: "folder")
                        }
                        .tag(NavigationRouter.Tab.browse)
                }
            }
            .animation(.easeInOut, value: networkService.isOnline)

            // Dismiss creator when tapping content area
            if showCreator {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { showCreator = false }
                    }
            }

            // Persistent FAB across all tabs
            if !showCreator {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showCreator = true }
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color(.systemBackground))
                                .frame(width: 52, height: 52)
                                .background(Color.primary)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 80) // above tab bar
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showCreator {
                InlineTaskCreator()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
