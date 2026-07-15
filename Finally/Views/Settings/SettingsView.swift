import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var sessions: [UserSession]
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider
    @State private var authService = NotionAuthService()

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
                        FinallyServerConnectView()
                    } label: {
                        Label("Add Finally Server", systemImage: "plus.circle")
                    }
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
                        Label("Update Notion Permissions", systemImage: "arrow.triangle.2.circlepath")
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
            .navigationTitle("Settings")
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
    }

    private func disconnectNotion() {
        KeychainHelper.deleteNotionToken()
        if let session = notionSession {
            modelContext.delete(session)
        }
        sessions.first { $0.providerIdentity == .finallyServer }?.isSelected = true
        try? modelContext.save()
    }

    private func removeServer(_ server: UserSession) {
        do {
            try FinallyServerAccountService.remove(server, store: modelContext)
        } catch {
            taskProvider.lastError = error.localizedDescription
        }
    }
}

private struct FinallyServerConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = "Finally Server"
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var authenticatedAccount: FinallyServerAuthenticatedAccount?
    @State private var selectedProject: FinallyServerProject?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Workspace") {
                TextField("Workspace name", text: $name)
                    .textContentType(.organizationName)
                TextField("https://tasks.example.com", text: $address)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(authenticatedAccount != nil)

                if let account = authenticatedAccount {
                    Picker("Workspace", selection: $selectedProject) {
                        Text("Select a workspace").tag(Optional<FinallyServerProject>.none)
                        ForEach(account.projects) { project in
                            Text(project.title).tag(Optional(project))
                        }
                    }
                }
            }

            Section("Account") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(authenticatedAccount != nil)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .disabled(authenticatedAccount != nil)

                if authenticatedAccount != nil {
                    Button("Use a different account") {
                        authenticatedAccount = nil
                        selectedProject = nil
                        password = ""
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("finally-server-connection-error")
                }
            }

            Section {
                primaryButton
            } footer: {
                Text("Finally stores the server token in Keychain. Your password is used only to sign in.")
            }
        }
        .navigationTitle("Connect Server")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            connectionTask?.cancel()
        }
        .onChange(of: selectedProject) { _, project in
            if name == "Finally Server", let project {
                name = project.title
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if #available(iOS 26, *) {
            Button(action: primaryAction) {
                primaryLabel
            }
            .buttonStyle(.glassProminent)
            .disabled(!canContinue || isWorking)
        } else {
            Button(action: primaryAction) {
                primaryLabel
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue || isWorking)
        }
    }

    @ViewBuilder
    private var primaryLabel: some View {
        if isWorking {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text(authenticatedAccount == nil ? "Find Workspaces" : "Connect")
                .frame(maxWidth: .infinity)
        }
    }

    private var canContinue: Bool {
        if authenticatedAccount == nil {
            return validatedURL != nil && !username.isEmpty && !password.isEmpty
        }
        return selectedProject != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var validatedURL: URL? {
        guard let url = URL(string: address),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func primaryAction() {
        if authenticatedAccount == nil {
            authenticate()
        } else {
            saveConnection()
        }
    }

    private func authenticate() {
        guard let url = validatedURL else { return }
        isWorking = true
        errorMessage = nil
        connectionTask?.cancel()
        connectionTask = Task {
            do {
                let account = try await accountService(for: url).authenticate(
                    baseURL: url,
                    username: username,
                    password: password
                )
                guard !Task.isCancelled else { return }
                guard !account.projects.isEmpty else {
                    errorMessage = "This account has no writable workspaces."
                    isWorking = false
                    return
                }
                authenticatedAccount = account
                selectedProject = account.projects.count == 1 ? account.projects[0] : nil
                isWorking = false
            } catch is CancellationError {
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func saveConnection() {
        guard let url = validatedURL,
              let account = authenticatedAccount,
              let selectedProject else { return }
        do {
            _ = try accountService(for: url).connect(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL: url,
                project: selectedProject,
                account: account,
                store: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accountService(for url: URL) -> FinallyServerAccountService {
        FinallyServerAccountService(
            api: URLSessionFinallyServerAPIClient(baseURL: url),
            authenticatedAPI: { token in
                URLSessionFinallyServerAPIClient(baseURL: url, token: token)
            }
        )
    }
}
