import SwiftData
import SwiftUI

/// The Daily Focus at the top of Today, headed "3 things to do" with one counter. A day the
/// personal agent proposed lists its picks with a Confirm button. A confirmed day shows the first
/// unfinished pick as a larger card and the rest below it.
struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void
    let onAddPick: () -> Void
    let onEditPicks: () -> Void
    var onReviewDay: (() -> Void)?

    @Query private var tasks: [TaskItem]

    private var resolved: [ResolvedDailyFocusPick] { focus.resolvedPicks(among: tasks) }
    private var deleted: [ResolvedDailyFocusPick] { resolved.filter { $0.task == nil } }
    private var actionable: [ResolvedDailyFocusPick] { focus.executionPicks(among: tasks) }

    var body: some View {
        if focus.isConfirmed {
            Section {
                if let item = actionable.first, let task = item.task {
                    CurrentPickCard(task: task, onOpen: { onSelectTask(task) })
                        .accessibilityIdentifier("daily-focus-current-task")
                } else if resolved.isEmpty {
                    emptyHint
                } else if deleted.isEmpty {
                    Label("All done for today", systemImage: "checkmark.seal")
                        .foregroundStyle(Palette.ink)
                        .cardRow()
                }
            } header: {
                header
            }
            Section {
                ForEach(Array(actionable.dropFirst())) { item in
                    if let task = item.task { taskRow(task) }
                }
                ForEach(deleted) { item in deletedRow(item) }
                actions
            }
        } else {
            Section {
                ForEach(resolved) { item in
                    if let task = item.task { taskRow(task) } else { deletedRow(item) }
                }
                if resolved.isEmpty { emptyHint }
                actions
            } header: {
                header
            }
            if !focus.picks.isEmpty {
                Section {
                    Button("Confirm") {
                        focus.confirm()
                        onChange()
                    }
                    .buttonStyle(.ink)
                    .accessibilityIdentifier("daily-focus-confirm")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(DailyFocusHeading.text(focusLimit: focus.focusLimit))
                .font(.cardTitle)
                .foregroundStyle(Palette.ink)
            Spacer()
            if !resolved.isEmpty {
                Text("\(resolved.filter { $0.task?.status == .done }.count) of \(resolved.count) done")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("daily-focus-progress")
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private var emptyHint: some View {
        Text("Pick a few tasks from Today.")
            .foregroundStyle(Palette.muted)
            .cardRow()
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: onAddPick) {
            Label(focus.isFull ? "Add an urgent task" : "Pick a task", systemImage: "plus.circle")
        }
        .accessibilityIdentifier("daily-focus-add-pick")
        .cardRow()
        if !focus.picks.isEmpty {
            Button("Edit", action: onEditPicks)
                .accessibilityIdentifier("daily-focus-edit-picks")
                .cardRow()
            if let onReviewDay {
                Button(action: onReviewDay) {
                    Label("Review the day", systemImage: "arrow.triangle.branch")
                }
                .accessibilityIdentifier("daily-focus-review-day")
                .cardRow()
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(task: task)
            .contentShape(Rectangle())
            .onTapGesture { onSelectTask(task) }
    }

    private func deletedRow(_ item: ResolvedDailyFocusPick) -> some View {
        HStack {
            Text("Deleted")
                .foregroundStyle(Palette.muted)
            Spacer()
            Button("Drop") {
                focus.remove(item.pick)
                onChange()
            }
            .buttonStyle(.borderless)
        }
        .cardRow()
        .accessibilityIdentifier("daily-focus-deleted-pick")
    }
}

/// The task to work on now, drawn larger than the rest with its own Done button.
private struct CurrentPickCard: View {
    @Bindable var task: TaskItem
    let onOpen: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskProviderCoordinator.self) private var taskProvider

    private var details: [String] {
        var parts: [String] = []
        if let date = TaskRowDate(for: task, at: Date()), date.kind == .deadline {
            parts.append("Deadline \(date.text)")
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
            HStack(alignment: .center, spacing: 12) {
                PriorityRing(color: task.priority?.color ?? Palette.low, isDone: false)
                    .accessibilityLabel(task.priority.map { "\($0.rawValue) priority" } ?? "No priority")
                Text(task.title)
                    .font(.cardTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
        .cardRow()
    }

    private func complete() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            let recycled = task.complete()
            if recycled {
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            } else {
                NotificationService.shared.cancelRemindersForTask(task, modelContext: modelContext)
            }
        }
        Task {
            await taskProvider.submitPendingChangesReportingFailure(for: task.pendingEdits, store: modelContext)
        }
    }
}

struct DailyFocusEditorView: View {
    let focus: DailyFocus
    let onChange: () -> Void
    @Query private var tasks: [TaskItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(focus.resolvedPicks(among: tasks)) { item in
                    Text(item.task?.title ?? "Deleted")
                        .foregroundStyle(item.task == nil ? Palette.muted : Palette.ink)
                        .cardRow()
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
            .paperList(background: Palette.sheet)
            .navigationTitle(DailyFocusHeading.text(focusLimit: focus.focusLimit))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .paperSheet()
    }
}
