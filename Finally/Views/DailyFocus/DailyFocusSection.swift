import SwiftData
import SwiftUI

struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void

    @Query private var tasks: [TaskItem]
    @State private var showPicker = false

    private var resolved: [ResolvedDailyFocusPick] { focus.resolvedPicks(among: tasks) }
    private var unfinished: [ResolvedDailyFocusPick] { resolved.filter { $0.task?.status != .done } }
    private var actionable: [ResolvedDailyFocusPick] { unfinished.filter { $0.task != nil } }

    var body: some View {
        if focus.isConfirmed {
            Section("Current") {
                if let item = actionable.first, let task = item.task {
                    taskRow(task.nextActionableSubtask ?? task)
                        .accessibilityIdentifier("daily-focus-current-task")
                } else if unfinished.isEmpty {
                    Label("Daily Focus complete", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Review the unavailable picks to continue.")
                        .foregroundStyle(.secondary)
                }
            }
            if actionable.count > 1 {
                Section("Next") {
                    ForEach(Array(actionable.dropFirst())) { item in
                        if let task = item.task { taskRow(task.nextActionableSubtask ?? task) }
                    }
                }
            }
            if unfinished.contains(where: { $0.task == nil }) {
                Section("Unavailable picks") {
                    ForEach(unfinished.filter { $0.task == nil }) { item in unavailableRow(item) }
                }
            }
        } else {
            Section {
                ForEach(resolved) { item in
                    if let task = item.task { taskRow(task) } else { unavailableRow(item) }
                }
                .onMove { source, destination in
                    focus.move(fromOffsets: source, toOffset: destination)
                    onChange()
                }
                .onDelete { offsets in
                    focus.remove(atOffsets: offsets)
                    onChange()
                }
                if resolved.isEmpty {
                    Text("Pick a few tasks for this day.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Proposed Daily Focus")
                    Spacer()
                    if resolved.count > 1 { EditButton().buttonStyle(.borderless) }
                }
            }
        }
        Section {
            Button {
                showPicker = true
            } label: {
                Label(focus.isFull ? "Add an urgent task" : "Add a pick", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("daily-focus-add-pick")
            if !focus.isConfirmed {
                Button {
                    focus.confirm()
                    onChange()
                } label: {
                    Label("Confirm Daily Focus", systemImage: "checkmark.seal")
                }
                .disabled(focus.picks.isEmpty)
                .accessibilityIdentifier("daily-focus-confirm")
            }
        } footer: {
            Text("\(focus.picks.count) of \(focus.focusLimit) picks · \(focus.isConfirmed ? "Confirmed" : "Awaiting confirmation")")
        }
        .sheet(isPresented: $showPicker) {
            DailyFocusPickerView(focus: focus, onPick: onChange)
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
            .contentShape(Rectangle())
            .onTapGesture { onSelectTask(task) }
    }

    private func unavailableRow(_ item: ResolvedDailyFocusPick) -> some View {
        HStack {
            Label("Task unavailable", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Drop") {
                focus.remove(item.pick)
                onChange()
            }
            .buttonStyle(.borderless)
        }
        .accessibilityIdentifier("daily-focus-unavailable-pick")
    }
}
