import SwiftData
import SwiftUI

/// The Daily Focus at the top of Today: "3 things to do" as a numbered list, with one counter on
/// the right. Each pick is a numbered row that keeps its place when it is done and collapses to
/// one short line. Each open slot up to the focus limit keeps its number and reads "Pick a task".
/// The number of the first open pick is orange, marking where to start. A long press and drag
/// reorders the picks, open or done. A day the personal agent proposed shows a Confirm button.
struct DailyFocusSection: View {
    let focus: DailyFocus
    let onChange: () -> Void
    let onSelectTask: (TaskItem) -> Void
    let onAddPick: () -> Void
    var onReviewDay: (() -> Void)?

    @Query private var tasks: [TaskItem]

    var body: some View {
        let list = DailyFocusList(focus: focus, tasks: tasks)
        Section {
            ForEach(list.rows) { row in
                if let task = row.task {
                    TaskRowView(
                        task: task,
                        focusAction: .remove { remove(row.pick) },
                        layout: .focus(number: row.number, isNext: row.isNext)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectTask(task) }
                    .accessibilityIdentifier(row.isNext ? "daily-focus-current-task" : "daily-focus-pick")
                } else {
                    unavailableRow(row)
                }
            }
            .onMove { source, destination in
                list.move(in: focus, fromOffsets: source, toOffset: destination)
                onChange()
            }
            ForEach(list.emptySlotNumbers, id: \.self) { number in
                emptySlot(number)
            }
            if let onReviewDay {
                Button(action: onReviewDay) {
                    Label("Review the day", systemImage: "arrow.triangle.branch")
                }
                .accessibilityIdentifier("daily-focus-review-day")
                .cardRow()
            }
        } header: {
            header(list)
        }
        if !focus.isConfirmed && !focus.picks.isEmpty {
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

    private func header(_ list: DailyFocusList) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(DailyFocusHeading.text(focusLimit: focus.focusLimit))
                .font(.focusHeading)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(list.status)
                .font(.meta)
                .foregroundStyle(Palette.muted)
                .accessibilityIdentifier("daily-focus-progress")
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    /// An open slot keeps its faint number. Tapping it opens the picker.
    private func emptySlot(_ number: Int) -> some View {
        Button(action: onAddPick) {
            HStack(spacing: 14) {
                slotNumber(number)
                Text("Pick a task")
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("daily-focus-add-pick")
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .cardRow()
        .moveDisabled(true)
    }

    /// A pick whose task is gone keeps its number and waits for Drop.
    private func unavailableRow(_ row: DailyFocusList.Row) -> some View {
        HStack(spacing: 14) {
            slotNumber(row.number)
            Text("Deleted")
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Drop") { remove(row.pick) }
                .buttonStyle(.borderless)
        }
        .frame(minHeight: 48)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .cardRow()
        .accessibilityIdentifier("daily-focus-deleted-pick")
    }

    private func slotNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.focusNumber)
            .monospacedDigit()
            .foregroundStyle(Palette.muted.opacity(0.4))
            .frame(width: 26)
            .accessibilityHidden(true)
    }

    /// Takes the task out of the day's picks. The task keeps its dates and stays open.
    private func remove(_ pick: DailyFocusPick) {
        focus.remove(pick)
        onChange()
    }
}
