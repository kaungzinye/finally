import SwiftUI
import SwiftData

struct KanbanFilterView: View {
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]
    @Binding var filterProjects: Set<String>
    @Binding var filterPriorities: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Projects") {
                    ForEach(projects, id: \.notionPageId) { project in
                        Button {
                            if filterProjects.contains(project.notionPageId) {
                                filterProjects.remove(project.notionPageId)
                            } else {
                                filterProjects.insert(project.notionPageId)
                            }
                        } label: {
                            HStack {
                                if let emoji = project.iconEmoji {
                                    Text(emoji)
                                }
                                Text(project.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filterProjects.contains(project.notionPageId) {
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
