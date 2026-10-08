import SwiftUI
import SwiftData

struct FinallyServerConnectView: View {
    var onConnected: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    @State private var name = "Finally Server"
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var authenticatedAccount: FinallyServerAuthenticatedAccount?
    @State private var selectedProject: FinallyServerProject?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectedWorkspace: UserSession?

    var body: some View {
        Form {
            Section("Workspace") {
                TextField("Workspace name", text: $name)
                    .textContentType(.organizationName)
                    .accessibilityIdentifier("server-workspace-name")
                    .disabled(isWorking || connectedWorkspace != nil)
                TextField("https://tasks.example.com", text: $address)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("server-address")
                    .disabled(isWorking || authenticatedAccount != nil)

                if let account = authenticatedAccount {
                    Picker("Workspace", selection: $selectedProject) {
                        Text("Select a workspace").tag(Optional<FinallyServerProject>.none)
                        ForEach(account.projects) { project in
                            Text(project.title).tag(Optional(project))
                        }
                    }
                    .disabled(isWorking || connectedWorkspace != nil)
                    .accessibilityIdentifier("server-workspace-picker")
                }
            }

            Section("Account") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("server-username")
                    .disabled(isWorking || authenticatedAccount != nil)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("server-password")
                    .disabled(isWorking || authenticatedAccount != nil)

                if authenticatedAccount != nil && connectedWorkspace == nil {
                    Button("Use a different account") {
                        authenticatedAccount = nil
                        selectedProject = nil
                        connectedWorkspace = nil
                        password = ""
                        errorMessage = nil
                    }
                    .disabled(isWorking)
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
            isWorking = false
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
            .accessibilityIdentifier("server-connect-action")
        } else {
            Button(action: primaryAction) {
                primaryLabel
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue || isWorking)
            .accessibilityIdentifier("server-connect-action")
        }
    }

    @ViewBuilder
    private var primaryLabel: some View {
        if isWorking {
            HStack {
                ProgressView()
                Text(authenticatedAccount == nil ? "Finding workspaces…" : "Syncing tasks…")
            }
            .frame(maxWidth: .infinity)
        } else {
            Text(connectedWorkspace != nil ? "Retry Sync" : authenticatedAccount == nil ? "Find Workspaces" : "Connect")
                .frame(maxWidth: .infinity)
        }
    }

    private var canContinue: Bool {
        if authenticatedAccount == nil {
            return validatedURL != nil
                && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
        }
        return selectedProject != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var validatedURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
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
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
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
        isWorking = true
        errorMessage = nil
        connectionTask?.cancel()
        do {
            let workspace: UserSession
            if let connectedWorkspace {
                workspace = connectedWorkspace
            } else {
                workspace = try accountService(for: url).connect(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: url,
                    project: selectedProject,
                    account: account,
                    store: modelContext
                )
                connectedWorkspace = workspace
            }
            connectionTask = Task {
                do {
                    try await taskProvider.synchronize(.launch, workspace: workspace, store: modelContext)
                    guard !Task.isCancelled else { return }
                    isWorking = false
                    onConnected()
                    dismiss()
                } catch is CancellationError {
                    isWorking = false
                } catch {
                    errorMessage = error.localizedDescription
                    isWorking = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
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
