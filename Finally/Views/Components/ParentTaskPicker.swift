import SwiftUI
import SwiftData

struct ParentTaskPicker: View {
    @Query(
        filter: #Predicate<TaskItem> { $0.isDeleted == false }
    )
    private var allTasks: [TaskItem]
    @Binding var selection: TaskItem?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var eligibleTasks: [TaskItem] {
        allTasks.filter { !$0.isSubtask }
    }

    private var filteredTasks: [TaskItem] {
        if searchText.isEmpty {
            return eligibleTasks
        }
        return eligibleTasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let selected = selection {
                    Section {
                        HStack {
                            Text(selected.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                selection = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Selected Parent")
                    }
                }

                Section {
                    ForEach(filteredTasks, id: \.notionPageId) { task in
                        Button {
                            selection = task
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let project = task.project {
                                        HStack(spacing: 4) {
                                            if let emoji = project.iconEmoji {
                                                Text(emoji).font(.caption2)
                                            }
                                            Text(project.title)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                if selection?.notionPageId == task.notionPageId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tasks")
                }
            }
            .searchable(text: $searchText, prompt: "Search tasks...")
            .navigationTitle("Link to Parent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
