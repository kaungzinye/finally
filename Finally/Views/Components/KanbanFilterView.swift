import SwiftUI
import SwiftData

struct KanbanFilterView: View {
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]
    @Query private var sessions: [UserSession]
    @Binding var filterProjects: Set<String>
    @Binding var filterPriorities: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Projects") {
                    ForEach(projects.scoped(to: sessions.selectedProviderWorkspace), id: \.externalProjectID) { project in
                        Button {
                            if filterProjects.contains(project.externalProjectID) {
                                filterProjects.remove(project.externalProjectID)
                            } else {
                                filterProjects.insert(project.externalProjectID)
                            }
                        } label: {
                            HStack {
                                if let emoji = project.iconEmoji {
                                    Text(emoji)
                                }
                                Text(project.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filterProjects.contains(project.externalProjectID) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Priority") {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button {
                            if filterPriorities.contains(priority.rawValue) {
                                filterPriorities.remove(priority.rawValue)
                            } else {
                                filterPriorities.insert(priority.rawValue)
                            }
                        } label: {
                            HStack {
                                Image(systemName: priority.icon)
                                    .foregroundStyle(priority.color)
                                Text(priority.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filterPriorities.contains(priority.rawValue) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        filterProjects.removeAll()
                        filterPriorities.removeAll()
                    }
                    .disabled(filterProjects.isEmpty && filterPriorities.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
