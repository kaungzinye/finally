import SwiftData
import SwiftUI

/// The Daily Focus picks for today, shown ahead of every deadline bucket.
/// Once the user confirms the day, the first unfinished pick becomes the current one.
struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void

    @Query private var tasks: [TaskItem]
    @State private var showPicker = false

    private var resolvedPicks: [ResolvedDailyFocusPick] {
        focus.resolvedPicks(among: tasks)
    }

    /// Once the day is confirmed, the first pick whose task is still open.
    private var current: (pick: DailyFocusPick, task: TaskItem)? {
        guard focus.isConfirmed else { return nil }
        for item in resolvedPicks {
            if let task = item.task, task.status != .done {
                return (item.pick, task)
            }
        }
        return nil
    }

    /// Positions in `focus.picks` of the picks listed below the current one.
    private var listedIndices: [Int] {
        resolvedPicks.indices.filter { resolvedPicks[$0].pick != current?.pick }
    }

    var body: some View {
        if let current {
            Section {
                CurrentPickCard(task: current.task, onOpen: { onSelectTask(current.task) })
            } header: {
                header
            }
        }

        Section {
            ForEach(listedIndices.map { resolvedPicks[$0] }) { item in
                if let task = item.task {
                    TaskRowView(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectTask(task) }
                } else {
                    unavailableRow
                }
            }
            .onMove { source, destination in
                let indices = listedIndices
                let fullDestination = destination < indices.count ? indices[destination] : (indices.last ?? -1) + 1
                focus.move(fromOffsets: IndexSet(source.map { indices[$0] }), toOffset: fullDestination)
                onChange()
            }
            .onDelete { offsets in
                let indices = listedIndices
                focus.remove(atOffsets: IndexSet(offsets.map { indices[$0] }))
                onChange()
            }

            if focus.isFull {
                leadingIconRow("checkmark.circle") {
                    Text("Daily Focus is full")
                        .font(.meta)
                        .foregroundStyle(Palette.muted)
                }
            } else {
                Button {
                    showPicker = true
                } label: {
                    leadingIconRow("plus") {
                        Text("Add a pick")
                            .foregroundStyle(Palette.ink)
                    }
                }
                .accessibilityIdentifier("daily-focus-add-pick")
            }

            if !focus.isConfirmed {
                Button("Confirm") {
                    focus.confirm()
                    onChange()
                }
                .buttonStyle(.ink)
                .disabled(focus.picks.isEmpty)
                .padding(.top, 8)
                .paperRow()
                .accessibilityIdentifier("daily-focus-confirm")
            }
        } header: {
            if current == nil {
                header
            }
        }
        .sheet(isPresented: $showPicker) {
            DailyFocusPickerView(focus: focus, onPick: onChange)
        }
    }

    private var unavailableRow: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.8, dash: [3, 3]))
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .padding(.leading, -11)
            Text("Task no longer available")
                .italic()
                .foregroundStyle(Palette.muted)
            Spacer()
        }
        .cardRow()
        .compactRowInsets()
        .accessibilityIdentifier("daily-focus-unavailable-pick")
    }

    /// A row whose leading symbol sits in the same column as the task rings.
    private func leadingIconRow<Content: View>(_ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.muted)
                .frame(width: 44, height: 44)
                .padding(.leading, -11)
            content()
            Spacer()
        }
        .contentShape(Rectangle())
        .cardRow()
        .compactRowInsets()
    }

    private var header: some View {
        SectionLabel(title: "Daily Focus") {
            HStack(spacing: 10) {
                Text("\(focus.picks.count) of \(focus.focusLimit)")
                if focus.isConfirmed {
                    Text("Confirmed")
                        .foregroundStyle(Palette.ink)
                }
                if focus.picks.count > 1 {
                    EditButton()
                        .font(.meta.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
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
