import SwiftData
import SwiftUI

/// The Daily Focus picks for today, shown ahead of every deadline bucket.
struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void

    @Query private var tasks: [TaskItem]
    @State private var showPicker = false

    private var resolvedPicks: [ResolvedDailyFocusPick] {
        focus.resolvedPicks(among: tasks)
    }

    var body: some View {
        Section {
            ForEach(resolvedPicks) { item in
                if let task = item.task {
                    TaskRowView(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectTask(task) }
                } else {
                    Label("Task no longer available", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("daily-focus-unavailable-pick")
                }
            }
            .onMove { source, destination in
                focus.move(fromOffsets: source, toOffset: destination)
                onChange()
            }
            .onDelete { offsets in
                focus.remove(atOffsets: offsets)
                onChange()
            }

            if focus.isFull {
                Label("Daily Focus is full", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    showPicker = true
                } label: {
                    Label("Add a pick", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("daily-focus-add-pick")
            }
        } header: {
            header
        }
        .sheet(isPresented: $showPicker) {
            DailyFocusPickerView(focus: focus, onPick: onChange)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Daily Focus")
            Spacer()
            Text("\(focus.picks.count) of \(focus.focusLimit)")
                .foregroundStyle(.secondary)
            if focus.isConfirmed {
                Label("Confirmed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Confirm") {
                    focus.confirm()
                    onChange()
                }
                .buttonStyle(.borderless)
                .disabled(focus.picks.isEmpty)
                .accessibilityIdentifier("daily-focus-confirm")
            }
            if focus.picks.count > 1 {
                EditButton()
                    .buttonStyle(.borderless)
            }
        }
        .textCase(nil)
    }
}
