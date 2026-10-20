import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var sessions: [UserSession]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @Environment(NotionAuthService.self) private var authService
    @AppStorage(AppConstants.focusLimitKey) private var focusLimit = DailyFocus.defaultFocusLimit

    private var notionSession: UserSession? {
        sessions.first { $0.providerIdentity == .notion }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                Section {
                    ForEach(sessions, id: \.id) { workspace in
                        CheckRow(isSelected: workspace.isSelected, action: { select(workspace) }) {
                            Label(
                                workspace.workspaceName,
                                systemImage: workspace.providerIdentity == .finallyServer ? "server.rack" : "building.2"
                            )
                        }
                    }

                    NavigationLink {
                        FinallyServerConnectView(onConnected: workspaceChanged)
                    } label: {
                        Label("Add a Finally Server", systemImage: "plus.circle")
                    }
                } header: {
                    SectionLabel("Workspaces")
                }

                Section {
                    ChoiceChips(choices: Array(DailyFocus.focusLimitRange), selection: $focusLimit) { "\($0)" }
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("focus-limit-choice")
                } header: {
                    SectionLabel("Things to do each day")
                } footer: {
                    SectionNote("How many tasks a new day holds. Days you already planned keep their count.")
                }

                Section {
                    NavigationLink {
                        DefaultDeadlineRemindersView()
                    } label: {
                        LabeledContent {
                            DefaultDeadlineRemindersLabel()
                        } label: {
                            Label("Deadline reminders", systemImage: "bell")
                        }
                    }
                    .accessibilityIdentifier("deadline-reminders-setting")

                    NavigationLink {
                        NotificationTimePickerView()
                    } label: {
                        LabeledContent {
                            DefaultReminderTimeLabel()
                        } label: {
                            Label("Default reminder time", systemImage: "clock")
                        }
                    }
                    .accessibilityIdentifier("default-reminder-time-setting")
                } header: {
                    SectionLabel("Notifications")
                }

                Section {
                    NavigationLink {
                        AppearanceSettingView()
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                    .accessibilityIdentifier("theme-setting")
                } header: {
                    SectionLabel("Appearance")
                }

                Section {
                    Button {
                        Task {
                            let success = await authService.startOAuthFlow(modelContext: modelContext)
                            if success {
                                reselectDatabases()
                            }
                        }
                    } label: {
                        Label(
                            authService.isAuthenticating ? "Connecting…" : notionSession == nil ? "Connect Notion" : "Update Notion permissions",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(authService.isAuthenticating)

                    if let message = authService.errorMessage {
                        Text(message)
                            .foregroundStyle(Palette.urgent)
                    }

                    NavigationLink {
                        DatabaseSetupGuideView()
                    } label: {
                        Label("Database setup guide", systemImage: "book")
                    }
                    .accessibilityIdentifier("database-setup-guide")
                } header: {
                    SectionLabel("Notion")
                }

                Section {
                    if notionSession != nil {
                        Button(role: .destructive) {
                            disconnectNotion()
                        } label: {
                            Label("Disconnect Notion", systemImage: "arrow.right.square")
                        }
                    }

                    ForEach(sessions.filter { $0.providerIdentity == .finallyServer }, id: \.id) { server in
                        Button(role: .destructive) {
                            removeServer(server)
                        } label: {
                            Label("Remove \(server.workspaceName)", systemImage: "trash")
                        }
                    }
                } header: {
                    SectionLabel("Account")
                }
                }
                .cardRow()
            }
            .foregroundStyle(Palette.ink)
            .paperList()
            .navigationTitle("Settings")
            .toolbar {
                ConfirmToolbarButton("Done") { dismiss() }
            }
        }
    }

    private func reselectDatabases() {
        guard let session = notionSession else { return }
        session.tasksDatabaseId = ""
        session.projectsDatabaseId = ""
        try? modelContext.save()
        NotificationCenter.default.post(name: .notionDatabasesReset, object: nil)
    }

    private func select(_ workspace: UserSession) {
        sessions.forEach { $0.isSelected = $0.id == workspace.id }
        try? modelContext.save()
        workspaceChanged()
    }

    private func disconnectNotion() {
        guard let session = notionSession else { return }
        do {
            let workspaceID = session.workspaceId
            let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>()).filter {
                $0.providerWorkspaceId == workspaceID
            }
            let projects = try modelContext.fetch(FetchDescriptor<ProjectItem>()).filter {
                $0.providerWorkspaceId == workspaceID
            }
            let focuses = try modelContext.fetch(FetchDescriptor<DailyFocus>()).filter {
                $0.storageWorkspaceID == workspaceID
            }
            focuses.forEach(modelContext.delete)
            tasks.forEach(modelContext.delete)
            projects.forEach(modelContext.delete)
            modelContext.delete(session)
            sessions.first { $0.providerIdentity == .finallyServer }?.isSelected = true
            try modelContext.save()
            KeychainHelper.deleteNotionToken()
            workspaceChanged()
        } catch {
            taskProvider.lastError = error.localizedDescription
        }
    }

    private func removeServer(_ server: UserSession) {
        do {
            try FinallyServerAccountService.remove(server, store: modelContext)
            workspaceChanged()
        } catch {
            taskProvider.lastError = error.localizedDescription
        }
    }

    private func workspaceChanged() {
        NotificationCenter.default.post(name: .providerWorkspaceChanged, object: nil)
    }
}

/// The gear at the leading edge of every tab's toolbar. It opens Settings.
private struct SettingsButton: ViewModifier {
    var isHidden: Bool
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !isHidden {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
    }
}

extension View {
    /// Adds the Settings gear to the toolbar's leading edge. A tab hides it while its own
    /// leading control, such as Cancel, takes the spot.
    func settingsButton(isHidden: Bool = false) -> some View {
        modifier(SettingsButton(isHidden: isHidden))
    }
}
