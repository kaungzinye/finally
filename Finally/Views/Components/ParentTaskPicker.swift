import SwiftUI
import SwiftData

struct ParentTaskPicker: View {
    @Query(
        filter: #Predicate<TaskItem> { $0.isDeleted == false }
    )
    private var allTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @Binding var selection: TaskItem?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var eligibleTasks: [TaskItem] {
        allTasks.scoped(to: sessions.selectedProviderWorkspace).filter { !$0.isSubtask }
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
                Group {
                    if let selected = selection {
                        Section {
                            HStack {
                                Text(selected.title)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Button {
                                    selection = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(Palette.muted)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove parent task")
                            }
                        } header: {
                            SectionLabel("Parent task")
                        }
                    }

                    Section {
                        ForEach(filteredTasks, id: \.externalTaskID) { task in
                            CheckRow(isSelected: selection?.externalTaskID == task.externalTaskID, action: {
                                selection = task
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .lineLimit(1)
                                    if let project = task.project {
                                        Text([project.iconEmoji, project.title].compactMap { $0 }.joined(separator: " "))
                                            .font(.meta)
                                            .foregroundStyle(Palette.muted)
                                    }
                                }
                            }
                        }
                    } header: {
                        SectionLabel("Tasks")
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .searchable(text: $searchText, prompt: "Search tasks")
            .navigationTitle("Parent task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .paperSheet()
    }
}
