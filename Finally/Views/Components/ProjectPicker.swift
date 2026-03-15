import SwiftUI
import SwiftData

struct ProjectPicker: View {
    @Binding var selection: ProjectItem?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]

    @State private var query: String = ""

    private var filteredProjects: [ProjectItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return projects }
        let lowercasedQuery = trimmed.lowercased()
        return projects.filter { $0.title.lowercased().contains(lowercasedQuery) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search projects", text: $query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }

                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("Inbox (No Project)")
                        Spacer()
                        if selection == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                ForEach(filteredProjects) { project in
                    Button {
                        selection = project
                        dismiss()
                    } label: {
                        HStack {
                            if let emoji = project.iconEmoji {
                                Text(emoji)
                            } else {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                            }
                            Text(project.title)
                            Spacer()
                            if selection?.notionPageId == project.notionPageId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
