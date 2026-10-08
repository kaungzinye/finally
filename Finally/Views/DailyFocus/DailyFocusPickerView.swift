import SwiftData
import SwiftUI

/// Picks one open task from the selected workspace into today's Daily Focus.
struct DailyFocusPickerView: View {
    let focus: DailyFocus
    let onPick: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<TaskItem> { task in
            task.statusRaw != "Complete" && task.isDeleted == false
        },
        sort: \TaskItem.deadline
    )
    private var openTasks: [TaskItem]
    @Query private var sessions: [UserSession]
    @State private var searchText = ""

    private var candidates: [TaskItem] {
        let picked = Set(focus.picks)
        let workspace = sessions.selectedProviderWorkspace
        return openTasks.filter { task in
            task.belongs(to: workspace)
                && !picked.contains(task.dailyFocusPick)
                && (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List(candidates, id: \.externalTaskID) { task in
                Button {
                    pick(task)
                } label: {
                    HStack {
                        Text(task.title)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if let deadline = task.deadline {
                            Text(deadline, style: .date)
                                .font(.meta)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .cardRow()
            }
            .paperList()
            .searchable(text: $searchText, prompt: "Search tasks")
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Nothing to pick",
                        systemImage: "scope",
                        description: Text("Every open task in this workspace is already in Daily Focus.")
                    )
                }
            }
            .navigationTitle("Add to Daily Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(focus.picks.count) of \(focus.focusLimit)")
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func pick(_ task: TaskItem) {
        do {
            try focus.add(task.dailyFocusPick)
            onPick()
            dismiss()
        } catch {
            dismiss()
        }
    }
}
