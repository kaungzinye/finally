import SwiftUI
import SwiftData

struct DatabasePickerView: View {
    var onComplete: () -> Void
    var onChooseProvider: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var databases: [NotionAPIService.NotionSearchResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTasksDb: String?
    @State private var selectedProjectsDb: String?
    @State private var isValidating = false
    @State private var validationErrors: [ValidationResult.Issue] = []
    @Environment(NotionAuthService.self) private var authService

    private let api = NotionAPIService()
    private let validator = SchemaValidator()

    var body: some View {
        NavigationStack {
            List {
                Group {
                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Finding your databases…")
                                .foregroundStyle(Palette.muted)
                                .padding(.leading, 8)
                        }
                    }
                } else if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Palette.urgent)
                        Button("Try again") {
                            Task { await loadDatabases() }
                        }
                    }
                } else if databases.isEmpty {
                    Section {
                        Text("Finally can't see any databases yet. Share your tasks database with Finally in Notion.")
                            .foregroundStyle(Palette.muted)
                        Button {
                            Task {
                                let success = await authService.startOAuthFlow(modelContext: modelContext)
                                if success {
                                    await loadDatabases()
                                }
                            }
                        } label: {
                            Label("Update Notion permissions", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(authService.isAuthenticating)
                        if let message = authService.errorMessage {
                            Text(message)
                                .foregroundStyle(Palette.urgent)
                        }
                    }
                } else {
                    Section {
                        ForEach(databases, id: \.id) { db in
                            CheckRow(isSelected: selectedTasksDb == db.id, action: { selectedTasksDb = db.id }) {
                                Text(db.title?.first?.plainText ?? "Untitled")
                            }
                        }
                    } header: {
                        SectionLabel("Tasks database")
                    }

                    Section {
                        CheckRow(isSelected: selectedProjectsDb == nil, action: { selectedProjectsDb = nil }) {
                            Text("None")
                        }
                        ForEach(databases, id: \.id) { db in
                            CheckRow(isSelected: selectedProjectsDb == db.id, action: { selectedProjectsDb = db.id }) {
                                Text(db.title?.first?.plainText ?? "Untitled")
                            }
                        }
                    } header: {
                        SectionLabel("Projects database, if you have one")
                    }

                    if !validationErrors.isEmpty {
                        Section {
                            ForEach(validationErrors, id: \.propertyName) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(Palette.high)
                                        Text(issue.propertyName)
                                            .fontWeight(.medium)
                                    }
                                    Text(issue.message)
                                        .font(.meta)
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                        } header: {
                            SectionLabel("Changes to make in Notion")
                        }
                    }
                }
                }
                .cardRow()
            }
            .paperList()
            .navigationTitle("Choose databases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ConfirmToolbarButton("Continue", isDisabled: selectedTasksDb == nil || isLoading || isValidating || authService.isAuthenticating) {
                    Task { await validateAndContinue() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", action: onChooseProvider)
                        .disabled(isValidating || authService.isAuthenticating)
                        .accessibilityIdentifier("choose-task-provider")
                }
            }
        }
        .task {
            await loadDatabases()
        }
    }

    private func loadDatabases() async {
        isLoading = true
        errorMessage = nil
        selectedTasksDb = nil
        selectedProjectsDb = nil
        validationErrors = []
        do {
            databases = try await api.searchDatabases()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func validateAndContinue() async {
        guard let tasksDbId = selectedTasksDb else { return }
        isValidating = true
        validationErrors = []

        do {
            let (taskResult, mappings) = try await validator.validateTasksDatabase(id: tasksDbId)

            if !taskResult.isValid {
                validationErrors = taskResult.issues
                isValidating = false
                return
            }

            var finalMappings = mappings

            // Validate projects if selected
            if let projectsDbId = selectedProjectsDb {
                let (projectResult, projectTitleKey) = try await validator.validateProjectsDatabase(id: projectsDbId)
                if !projectResult.isValid {
                    validationErrors = projectResult.issues
                    isValidating = false
                    return
                }
                finalMappings.projectTitleProperty = projectTitleKey
            }

            // Save to session
            guard let session = try modelContext.selectedProviderWorkspace(),
                  session.providerIdentity == .notion else {
                errorMessage = "Connect a Notion workspace to select its databases."
                isValidating = false
                return
            }
            session.tasksDatabaseId = tasksDbId
            session.projectsDatabaseId = selectedProjectsDb ?? ""
            session.propertyMappings = finalMappings
            try modelContext.save()

            isValidating = false
            onComplete()
        } catch {
            validationErrors = [.init(
                propertyName: "Connection",
                expectedType: "",
                message: error.localizedDescription
            )]
            isValidating = false
        }
    }
}
