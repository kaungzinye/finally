import SwiftData
import SwiftUI

struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void

    @Query private var tasks: [TaskItem]
    @State private var showPicker = false
    @State private var showEditor = false

    private var resolved: [ResolvedDailyFocusPick] { focus.resolvedPicks(among: tasks) }
    private var unfinished: [ResolvedDailyFocusPick] { resolved.filter { $0.task?.status != .done } }
    private var actionable: [ResolvedDailyFocusPick] { unfinished.filter { $0.task != nil } }

    var body: some View {
        if focus.isConfirmed {
            Section("Current") {
                if let item = actionable.first, let task = item.task {
                    CurrentPickCard(task: task.nextActionableSubtask ?? task, onOpen: { onSelectTask(task.nextActionableSubtask ?? task) })
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
            if focus.isConfirmed {
                Button("Edit picks") { showEditor = true }
                    .accessibilityIdentifier("daily-focus-edit-picks")
            }
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
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                List {
                    ForEach(resolved) { item in
                        Text(item.task?.title ?? "Task unavailable").cardRow()
                    }
                    .onMove { source, destination in
                        focus.move(fromOffsets: source, toOffset: destination)
                        onChange()
                    }
                    .onDelete { offsets in
                        focus.remove(atOffsets: offsets)
                        onChange()
                    }
                }
                .paperList()
                .navigationTitle("Edit picks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showEditor = false }
                    }
                }
            }
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

/// The pick to work on now, drawn larger than the rest with an ink edge.
private struct CurrentPickCard: View {
    @Bindable var task: TaskItem
    let onOpen: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    private var details: [String] {
        var parts: [String] = []
        if let deadline = task.deadline {
            parts.append("Due \(deadline.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
        }
        if let project = task.project?.title {
            parts.append(project)
        }
        if task.hasSubtasks {
            let progress = task.subtaskProgress
            parts.append("\(progress.done) of \(progress.total) subtasks")
        }
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOW")
                    .font(.eyebrow)
                    .tracking(0.5)
                    .foregroundStyle(Palette.muted)
                Spacer()
                if let priority = task.priority {
                    Label(priority.rawValue, systemImage: priority.icon)
                        .font(.meta)
                        .foregroundStyle(priority.color)
                }
            }

            Text(task.title)
                .font(.cardTitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(3)

            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.meta)
                    .foregroundStyle(task.isOverdue ? Palette.urgent : Palette.muted)
            }

            Button(action: complete) {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(.ink)
            .padding(.top, 6)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .listRowBackground(
            ContainerRelativeShape()
                .fill(Palette.card)
                .strokeBorder(Palette.ink.opacity(0.55), lineWidth: 1.5)
        )
    }

    private func complete() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            let recycled = task.complete()
            if recycled {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task)
            }
        }
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: [task], store: modelContext)
        }
    }
}

/// One small stamp per pick, filled once its task is done.
struct DailyFocusProgress: View {
    let focus: DailyFocus

    @Query private var tasks: [TaskItem]

    private var doneFlags: [Bool] {
        focus.resolvedPicks(among: tasks).map { $0.task?.status == .done }
    }

    var body: some View {
        let flags = doneFlags
        HStack(spacing: 6) {
            ForEach(Array(flags.enumerated()), id: \.offset) { _, isDone in
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(isDone ? Palette.ink : Color.clear)
                    .strokeBorder(isDone ? Palette.ink : Palette.hairline, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-4))
            }
            Text("\(flags.filter { $0 }.count) of \(flags.count) done")
                .font(.meta)
                .foregroundStyle(Palette.muted)
                .padding(.leading, 6)
        }
        .accessibilityElement(children: .combine)
    }
}
