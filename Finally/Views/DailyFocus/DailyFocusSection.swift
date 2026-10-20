import SwiftData
import SwiftUI

/// The Daily Focus at the top of Today, headed "3 things to do" with one counter. Each open slot
/// up to the focus limit reads "Pick a task". A day the personal agent proposed lists its picks
/// with a Confirm button. A confirmed day shows the first unfinished pick as a larger card and the
/// rest below it. A pick swipes away with Remove and reorders with a long press and drag.
struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void
    let onAddPick: () -> Void
    var onReviewDay: (() -> Void)?

    @Query private var tasks: [TaskItem]

    private var resolved: [ResolvedDailyFocusPick] { focus.resolvedPicks(among: tasks) }
    private var deleted: [ResolvedDailyFocusPick] { resolved.filter { $0.task == nil } }
    private var actionable: [ResolvedDailyFocusPick] { focus.executionPicks(among: tasks) }
    private var openSlots: Int { max(focus.focusLimit - focus.picks.count, 0) }

    var body: some View {
        if focus.isConfirmed {
            Section {
                ForEach(Array(actionable.enumerated()), id: \.element.id) { index, item in
                    if let task = item.task {
                        if index == 0 {
                            CurrentPickCard(task: task, onOpen: { onSelectTask(task) })
                                .swipeActions(edge: .trailing) { removeButton(item.pick) }
                                .accessibilityIdentifier("daily-focus-current-task")
                        } else {
                            taskRow(task, pick: item.pick)
                        }
                    }
                }
                .onMove { source, destination in
                    focus.move(actionable.map(\.pick), fromOffsets: source, toOffset: destination)
                    onChange()
                }
                if actionable.isEmpty && !resolved.isEmpty && deleted.isEmpty {
                    Label("All done for today", systemImage: "checkmark.seal")
                        .foregroundStyle(Palette.ink)
                        .cardRow()
                }
                ForEach(deleted) { item in deletedRow(item) }
                actions
            } header: {
                header
            }
        } else {
            Section {
                ForEach(resolved) { item in
                    if let task = item.task { taskRow(task, pick: item.pick) } else { deletedRow(item) }
                }
                .onMove { source, destination in
                    focus.move(fromOffsets: source, toOffset: destination)
                    onChange()
                }
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

    /// One "Pick a task" row per open slot, then Review the day when it shows.
    @ViewBuilder
    private var actions: some View {
        ForEach(0..<openSlots, id: \.self) { _ in
            Button(action: onAddPick) {
                Label("Pick a task", systemImage: "plus")
                    .foregroundStyle(Palette.muted)
            }
            .accessibilityIdentifier("daily-focus-add-pick")
            .cardRow()
        }
        if let onReviewDay {
            Button(action: onReviewDay) {
                Label("Review the day", systemImage: "arrow.triangle.branch")
            }
            .accessibilityIdentifier("daily-focus-review-day")
            .cardRow()
        }
    }

    private func removeButton(_ pick: DailyFocusPick) -> some View {
        Button(role: .destructive) {
            remove(pick)
        } label: {
            Label("Remove", systemImage: "minus.circle")
        }
    }

    /// Takes the task out of the day's picks. The task keeps its dates and stays open.
    private func remove(_ pick: DailyFocusPick) {
        focus.remove(pick)
        onChange()
    }

    private func taskRow(_ task: TaskItem, pick: DailyFocusPick) -> some View {
        TaskRowView(task: task, focusAction: .remove { remove(pick) })
            .contentShape(Rectangle())
            .onTapGesture { onSelectTask(task) }
    }

    private func deletedRow(_ item: ResolvedDailyFocusPick) -> some View {
        HStack {
            Text("Deleted")
                .foregroundStyle(Palette.muted)
            Spacer()
            Button("Drop") { remove(item.pick) }
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
