import SwiftData
import SwiftUI

/// Adds a task, with a user-chosen displacement when Daily Focus is full.
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
    @State private var sourceWorkspaceID: String?
    @State private var replacementTask: TaskItem?
    @State private var errorMessage: String?
    @Query private var allTasks: [TaskItem]

    private var sourceWorkspace: UserSession? {
        sessions.first { $0.workspaceId == (sourceWorkspaceID ?? focus.storageWorkspaceID) }
    }

    private var candidates: [TaskItem] {
        let picked = Set(focus.picks)
        let workspace = sourceWorkspace
        return openTasks.filter { task in
            task.nextActionableSubtask == nil
                && task.belongs(to: workspace)
                && !picked.contains(task.dailyFocusPick)
                && (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Task provider workspace", selection: Binding(
                        get: { sourceWorkspaceID ?? focus.storageWorkspaceID },
                        set: { sourceWorkspaceID = $0 }
                    )) {
                        ForEach(sessions, id: \.workspaceId) { workspace in
                            Text(workspace.workspaceName).tag(workspace.workspaceId)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("daily-focus-source-workspace")
                    .cardRow()
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(candidates) { task in
                    Button {
                        pick(task)
                    } label: {
                        HStack {
                            Text(task.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let deadline = task.deadline {
                                Text(deadline, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .paperList()
            .searchable(text: $searchText, prompt: "Search tasks")
            .safeAreaInset(edge: .bottom) {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Nothing to pick",
                        systemImage: "scope",
                        description: Text(searchText.isEmpty ? "Choose an open task or an actionable step in this provider workspace." : "Try another search.")
                    )
                }
            }
            .navigationTitle("Add to Daily Focus")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $replacementTask) { task in
                NavigationStack {
                    List(focus.resolvedPicks(among: allTasks)) { item in
                        Button {
                            do {
                                try focus.replace(item.pick, with: task.dailyFocusPick)
                                onPick()
                                replacementTask = nil
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                replacementTask = nil
                            }
                        } label: {
                            Label(item.task?.title ?? "Unavailable task", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    .navigationTitle("Choose a pick to replace")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top) {
                        Text("Make room for \(task.title). The displaced task stays in its provider.")
                            .font(.subheadline).foregroundStyle(.secondary).padding()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { replacementTask = nil }
                        }
                    }
                }
            }
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
        if focus.isFull {
            replacementTask = task
            return
        }
        do {
            try focus.add(task.dailyFocusPick)
            onPick()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
