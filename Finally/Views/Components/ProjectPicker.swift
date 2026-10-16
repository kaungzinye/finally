import SwiftUI
import SwiftData

struct ProjectPicker: View {
    @Binding var selection: ProjectItem?
    /// The task whose workspace supplies the projects. Capture leaves it out and uses the selected workspace.
    var task: TaskItem? = nil
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]
    @Query private var sessions: [UserSession]

    @State private var query: String = ""

    private var filteredProjects: [ProjectItem] {
        let selectedProjects = task.map { projects.available(to: $0) } ?? projects.scoped(to: sessions.selectedProviderWorkspace)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return selectedProjects }
        let lowercasedQuery = trimmed.lowercased()
        return selectedProjects.filter { $0.title.lowercased().contains(lowercasedQuery) }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Palette.muted)
                            TextField("Search projects", text: $query)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                        }
                    }

                    Section {
                        CheckRow(isSelected: selection == nil, action: { choose(nil) }) {
                            Image(systemName: "tray")
                                .foregroundStyle(Palette.muted)
                            Text("Inbox")
                        }

                        ForEach(filteredProjects) { project in
                            CheckRow(isSelected: selection?.externalProjectID == project.externalProjectID, action: { choose(project) }) {
                                if let emoji = project.iconEmoji {
                                    Text(emoji)
                                } else {
                                    Image(systemName: "folder")
                                        .foregroundStyle(Palette.muted)
                                }
                                Text(project.title)
                            }
                        }
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .paperSheet()
    }

    private func choose(_ project: ProjectItem?) {
        selection = project
        dismiss()
    }
}
