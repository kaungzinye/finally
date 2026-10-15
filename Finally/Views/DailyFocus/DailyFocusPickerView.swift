import SwiftData
import SwiftUI

/// Picks a task for the day, listing Today's tasks first. A full day takes a pick only by
/// replacing the one the user chooses.
struct DailyFocusPickerView: View {
    let focus: DailyFocus
    let onPick: (TaskItem) -> Void

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
        let representedSteps = Set(focus.executionPicks(among: allTasks).compactMap { $0.task?.dailyFocusPick })
        let workspace = sourceWorkspace
        return openTasks.filter { task in
            task.nextActionableSubtask == nil
                && task.belongs(to: workspace)
                && !picked.contains(task.dailyFocusPick)
                && !representedSteps.contains(task.dailyFocusPick)
                && (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var todayCandidates: [TaskItem] {
        Today.members(of: candidates, at: Date()).map(\.task)
    }

    private var otherCandidates: [TaskItem] {
        let today = Set(todayCandidates.map(\.persistentModelID))
        return candidates.filter { !today.contains($0.persistentModelID) }
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
                if !todayCandidates.isEmpty {
                    Section {
                        ForEach(todayCandidates) { candidateRow($0) }
                    } header: {
                        SectionLabel("Today")
                    }
                }
                if !otherCandidates.isEmpty {
                    Section {
                        ForEach(otherCandidates) { candidateRow($0) }
                    } header: {
                        SectionLabel("Everything else")
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
            .navigationTitle("Pick a task")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $replacementTask) { task in
                NavigationStack {
                    List(focus.resolvedPicks(among: allTasks)) { item in
                        Button {
                            do {
                                try focus.pick(task, replacing: item.pick)
                                onPick(task)
                                replacementTask = nil
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                replacementTask = nil
                            }
                        } label: {
                            Label(item.task?.title ?? "Deleted", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    .navigationTitle("Choose a task to replace")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top) {
                        Text("Make room for \(task.title). The task you replace keeps its dates.")
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
            try focus.pick(task)
            onPick(task)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func candidateRow(_ task: TaskItem) -> some View {
        Button {
            pick(task)
        } label: {
            HStack {
                Text(task.title)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let date = TaskRowDate(for: task, at: Date()) {
                    Text(date.text)
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .cardRow()
    }
}
