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
                Section("Workspaces") {
                    ForEach(sessions, id: \.id) { workspace in
                        Button {
                            select(workspace)
                        } label: {
                            HStack {
                                Label(
                                    workspace.workspaceName,
                                    systemImage: workspace.providerIdentity == .finallyServer ? "server.rack" : "building.2"
                                )
                                Spacer()
                                if workspace.isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }

                    NavigationLink {
                        FinallyServerConnectView(onConnected: workspaceChanged)
                    } label: {
                        Label("Add Finally Server", systemImage: "plus.circle")
                    }
                }

                Section {
                    Stepper(value: $focusLimit, in: DailyFocus.focusLimitRange) {
                        HStack {
                            Label("Focus limit", systemImage: "scope")
                            Spacer()
                            Text("\(focusLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("focus-limit-stepper")
                } header: {
                    Text("Daily Focus")
                } footer: {
                    Text("New Daily Focus days use this limit, one to five picks. Each existing day keeps its limit.")
                }

                Section("Notifications") {
                    NavigationLink {
                        NotificationTimePickerView()
                    } label: {
                        HStack {
                            Label("Default Reminder Time", systemImage: "clock")
                            Spacer()
                            DefaultReminderTimeLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingView()
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                }

                Section("Notion") {
                    if let notionSession {
                        HStack {
                            Label("Workspace", systemImage: "building.2")
                            Spacer()
                            Text(notionSession.workspaceName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task {
                            let success = await authService.startOAuthFlow(modelContext: modelContext)
                            if success {
                                reselectDatabases()
                            }
                        }
                    } label: {
                        Label(
                            authService.isAuthenticating ? "Connecting…" : notionSession == nil ? "Connect Notion" : "Update Notion Permissions",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(authService.isAuthenticating)

                    if let message = authService.errorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }

                    NavigationLink {
                        DatabaseSetupGuideView()
                    } label: {
                        Label("Database Setup Guide", systemImage: "book")
                    }
                }

                Section("Account") {
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
                }
            }
            .paperList()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
