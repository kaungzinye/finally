import SwiftUI
import SwiftData

struct FinallyServerConnectView: View {
    var onConnected: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @FocusState private var passwordIsFocused: Bool
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
            Group {
                Section {
                    TextField("Workspace name", text: $name)
                        .textContentType(.organizationName)
                        .accessibilityIdentifier("server-workspace-name")
                        .disabled(isWorking)
                    TextField("https://tasks.example.com", text: $address)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("server-address")
                        .disabled(isWorking || authenticatedAccount != nil)
                } header: {
                    SectionLabel("Server")
                }

                if let account = authenticatedAccount {
                    Section {
                        ForEach(account.projects) { project in
                            CheckRow(isSelected: selectedProject == project, action: { selectedProject = project }) {
                                Text(project.title)
                            }
                            .disabled(isWorking)
                        }
                    } header: {
                        SectionLabel("Workspace")
                    }
                    .accessibilityIdentifier("server-workspace-picker")
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("server-username")
                        .disabled(isWorking || authenticatedAccount != nil)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("server-password")
                        .focused($passwordIsFocused)
                        .submitLabel(.done)
                        .onSubmit { passwordIsFocused = false }
                        .disabled(isWorking || authenticatedAccount != nil)

                    if authenticatedAccount != nil {
                        Button("Use a different account") {
                            authenticatedAccount = nil
                            selectedProject = nil
                            password = ""
                            errorMessage = nil
                        }
                        .foregroundStyle(Palette.ink)
                        .disabled(isWorking)
                    }
                } header: {
                    SectionLabel("Account")
                }
            }
            .cardRow()

            if let errorMessage {
                Section {
                    Callout(message: errorMessage)
                        .accessibilityIdentifier("finally-server-connection-error")
                        .paperRow()
                }
            }

            Section {
                Button(action: primaryAction) {
                    primaryLabel
                }
                .buttonStyle(.ink)
                .disabled(!canContinue || isWorking)
                .accessibilityIdentifier("server-connect-action")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                SectionNote("Finally keeps the server's sign-in token in your Keychain. Your password is only used to sign in.")
                    .padding(.top, 8)
            }
        }
        .paperList()
        .navigationTitle("Connect a server")
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
    private var primaryLabel: some View {
        if isWorking {
            HStack {
                ProgressView()
                    .tint(Palette.onInk)
                Text(authenticatedAccount == nil ? "Finding workspaces…" : "Connecting…")
            }
        } else {
            Text(authenticatedAccount == nil ? "Find workspaces" : "Connect")
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
                    errorMessage = "This account has no workspaces you can edit."
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
        do {
            _ = try accountService(for: url).connect(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL: url,
                project: selectedProject,
                account: account,
                store: modelContext
            )
            isWorking = false
            onConnected()
            dismiss()
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
