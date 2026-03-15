import SwiftUI
import SwiftData

struct DatabasePickerView: View {
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var databases: [NotionAPIService.NotionSearchResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTasksDb: String?
    @State private var selectedProjectsDb: String?
    @State private var isValidating = false
    @State private var validationErrors: [ValidationResult.Issue] = []
    @State private var authService = NotionAuthService()

    private let api = NotionAPIService()
    private let validator = SchemaValidator()

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading databases...")
                                .padding(.leading, 8)
                        }
                    }
                } else if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { await loadDatabases() }
                        }
                    }
                } else if databases.isEmpty {
                    Section {
                        Text("No databases found. You may need to share pages with this integration in Notion.")
                            .foregroundStyle(.secondary)
                        Button {
                            Task {
                                let success = await authService.startOAuthFlow(modelContext: modelContext)
                                if success {
                                    await loadDatabases()
                                }
                            }
                        } label: {
                            Label("Update Notion Permissions", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } else {
                    Section("Tasks Database (Required)") {
                        ForEach(databases, id: \.id) { db in
                            Button {
                                selectedTasksDb = db.id
                            } label: {
                                HStack {
                                    Text(db.title?.first?.plainText ?? "Untitled")
                                    Spacer()
                                    if selectedTasksDb == db.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }

                    Section("Projects Database (Optional)") {
                        Button {
                            selectedProjectsDb = nil
                        } label: {
                            HStack {
                                Text("None")
                                Spacer()
                                if selectedProjectsDb == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }

                        ForEach(databases, id: \.id) { db in
                            Button {
                                selectedProjectsDb = db.id
                            } label: {
                                HStack {
                                    Text(db.title?.first?.plainText ?? "Untitled")
                                    Spacer()
                                    if selectedProjectsDb == db.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }

                    if !validationErrors.isEmpty {
                        Section("Schema Issues") {
                            ForEach(validationErrors, id: \.propertyName) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(issue.propertyName)
                                            .fontWeight(.medium)
                                    }
                                    Text(issue.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Databases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        Task { await validateAndContinue() }
                    }
                    .disabled(selectedTasksDb == nil || isValidating)
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
            let descriptor = FetchDescriptor<UserSession>()
            if let session = try? modelContext.fetch(descriptor).first {
                session.tasksDatabaseId = tasksDbId
                session.projectsDatabaseId = selectedProjectsDb ?? ""
                session.propertyMappings = finalMappings
                try modelContext.save()
            }

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
