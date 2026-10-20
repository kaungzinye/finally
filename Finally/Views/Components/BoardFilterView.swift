import SwiftUI
import SwiftData

struct BoardFilterView: View {
    @Query(sort: \ProjectItem.title) private var projects: [ProjectItem]
    @Query private var sessions: [UserSession]
    @Binding var filterProjects: Set<String>
    @Binding var filterPriorities: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(projects.scoped(to: sessions.selectedProviderWorkspace), id: \.externalProjectID) { project in
                            CheckRow(isSelected: filterProjects.contains(project.externalProjectID), action: {
                                toggle(project.externalProjectID, in: &filterProjects)
                            }) {
                                if let emoji = project.iconEmoji {
                                    Text(emoji)
                                }
                                Text(project.title)
                            }
                        }
                    } header: {
                        SectionLabel("Projects")
                    }

                    Section {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            CheckRow(isSelected: filterPriorities.contains(priority.rawValue), action: {
                                toggle(priority.rawValue, in: &filterPriorities)
                            }) {
                                PriorityRing(color: priority.color, isDone: false)
                                Text(priority.rawValue)
                            }
                        }
                    } header: {
                        SectionLabel("Priority")
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        filterProjects.removeAll()
                        filterPriorities.removeAll()
                    }
                    .disabled(filterProjects.isEmpty && filterPriorities.isEmpty)
                }
                ConfirmToolbarButton("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .paperSheet()
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
