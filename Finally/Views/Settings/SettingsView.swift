import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var sessions: [UserSession]
    @Environment(\.modelContext) private var modelContext
    @State private var authService = NotionAuthService()

    private var session: UserSession? { sessions.first }

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingView()
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                }

                Section("Notion") {
                    if let session {
                        HStack {
                            Label("Workspace", systemImage: "building.2")
                            Spacer()
                            Text(session.workspaceName)
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
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        Label("Disconnect Notion", systemImage: "arrow.right.square")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func reselectDatabases() {
        guard let session else { return }
        session.tasksDatabaseId = ""
        session.projectsDatabaseId = ""
        try? modelContext.save()
        NotificationCenter.default.post(name: .notionDatabasesReset, object: nil)
    }

    private func disconnect() {
        KeychainHelper.deleteNotionToken()
        if let session {
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}
