import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Focus widget

/// Medium. The open Daily Focus picks under "3 things to do". A finished pick drops off. A Daily
/// Focus waiting for confirmation lists its picks for review instead, and opens Today.
struct FocusWidgetView: View {
    let day: WidgetDay
    let date: Date

    private static let rows = 4

    var body: some View {
        if day.awaitsConfirmation {
            review
        } else {
            focus
        }
    }

    private var review: some View {
        let picks = day.unconfirmedPicks
        let shown = picks.count > Self.rows ? Self.rows - 1 : Self.rows
        return VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(title: day.confirmHeading)
            ForEach(picks.prefix(shown)) { task in
                Text(task.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(height: WidgetTaskRow.height, alignment: .leading)
            }
            if picks.count > shown {
                Text("+\(picks.count - shown) more")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
                    .frame(height: WidgetTaskRow.height, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(AppConstants.todayURL)
    }

    private var focus: some View {
        let picks = day.openPicks
        let shown = picks.count > Self.rows ? Self.rows - 1 : Self.rows
        return VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(title: day.focusHeading)
            if picks.isEmpty {
                Spacer(minLength: 0)
                Text(day.picks.isEmpty ? "Pick a few tasks from Today." : "All done for today")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            } else {
                ForEach(picks.prefix(shown)) { task in
                    WidgetTaskRow(task: task, date: date)
                }
                if picks.count > shown {
                    MoreRow(count: picks.count - shown)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Now widget

/// Small. The first open pick, large, with its deadline, its place among the picks, and Done. A
/// Daily Focus waiting for confirmation asks the user to open Today instead.
struct NowWidgetView: View {
    let day: WidgetDay
    let date: Date

    var body: some View {
        if day.awaitsConfirmation {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.confirmHeading)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Open to confirm")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(AppConstants.todayURL)
        } else if let task = day.nowPick {
            VStack(alignment: .leading, spacing: 4) {
                if let place = day.nowPickPlace {
                    Text(place)
                        .font(.eyebrow)
                        .foregroundStyle(Palette.muted)
                }
                Text(task.title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                DeadlineText(task: task, date: date)
                Spacer(minLength: 4)
                Button(intent: CompleteTaskIntent(task: task)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.action)
                        .foregroundStyle(Palette.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(task.url)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.focusHeading)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(day.picks.isEmpty ? "Pick a few tasks from Today." : "All done for today")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Today widget

/// Large. All of Today in Today-tab order, then Coming up while rows remain.
struct TodayWidgetView: View {
    let day: WidgetDay
    let date: Date

    private static let rows = 11

    var body: some View {
        let layout = day.todayWidgetLayout(rows: Self.rows)
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(title: "Today", detail: date.formatted(.dateTime.weekday(.wide)))
            if layout.today.isEmpty && layout.comingUp.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing on your plate today.")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            }
            ForEach(layout.today) { task in
                WidgetTaskRow(task: task, date: date)
            }
            if layout.moreCount > 0 {
                MoreRow(count: layout.moreCount)
            }
            if !layout.comingUp.isEmpty {
                Text("COMING UP")
                    .font(.eyebrow)
                    .tracking(0.5)
                    .foregroundStyle(Palette.muted)
                    .frame(height: WidgetTaskRow.height, alignment: .bottomLeading)
                ForEach(layout.comingUp) { task in
                    WidgetTaskRow(task: task, date: date)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lock screen

/// Circular. One section per task in Today, ink for the picks and muted for the rest. A section
/// fills once its task is done, and the center counts done out of total.
struct LockScreenRingView: View {
    let day: WidgetDay

    var body: some View {
        let sections = day.ringSections
        ZStack {
            AccessoryWidgetBackground()
            SectionedRing(sections: sections)
                .padding(3)
            Text("\(sections.filter(\.isDone).count)/\(sections.count)")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
        }
        .widgetURL(URL(string: "\(AppConstants.urlScheme)://"))
    }
}

/// Rectangular. The first open pick and its deadline, or the Daily Focus waiting for confirmation.
struct LockScreenNowView: View {
    let day: WidgetDay
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if day.awaitsConfirmation {
                Text(day.confirmHeading)
                    .font(.headline)
                Text("Open to confirm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let task = day.nowPick {
                if let place = day.nowPickPlace {
                    Text(place)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                if let rowDate = TaskRowDate(for: task, at: date), rowDate.kind == .deadline {
                    Text("Deadline \(rowDate.text)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(day.focusHeading)
                    .font(.headline)
                Text(day.picks.isEmpty ? "Pick a few tasks from Today." : "All done for today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(day.awaitsConfirmation ? AppConstants.todayURL : day.nowPick?.url)
    }
}

private struct SectionedRing: View {
    let sections: [RingSection]

    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            if sections.isEmpty {
                Circle().stroke(Palette.muted.opacity(0.35), lineWidth: lineWidth)
            }
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                let span = 1 / Double(sections.count)
                let gap = sections.count > 1 ? min(0.02, span / 4) : 0
                Circle()
                    .trim(from: Double(index) * span + gap / 2, to: Double(index + 1) * span - gap / 2)
                    .stroke(color(for: section), style: StrokeStyle(lineWidth: lineWidth))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func color(for section: RingSection) -> Color {
        let color = section.isFocus ? Palette.ink : Palette.muted
        return section.isDone ? color : color.opacity(0.45)
    }
}

// MARK: - Shared pieces

/// One task on one line. The ring finishes the task, and the rest of the row opens it.
struct WidgetTaskRow: View {
    static let height: CGFloat = 26

    let task: WidgetTask
    let date: Date

    var body: some View {
        let reason = Today.reason(for: task, at: date)
        HStack(spacing: 8) {
            Button(intent: CompleteTaskIntent(task: task)) {
                PriorityRing(color: task.priority?.color ?? Palette.low, isDone: !task.isOpen, diameter: 17)
                    .frame(width: 24, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete")
            Link(destination: task.url) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundStyle(reason == .missedScheduledDay ? Palette.muted : Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let rowDate = TaskRowDate(for: task, at: date) {
                        Text(rowDate.text)
                            .font(.meta)
                            .foregroundStyle(reason == .overdue ? Palette.urgent : Palette.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: Self.height)
    }
}

/// The deadline line under a pick, red once the deadline has passed.
private struct DeadlineText: View {
    let task: WidgetTask
    let date: Date

    var body: some View {
        if let rowDate = TaskRowDate(for: task, at: date), rowDate.kind == .deadline {
            Text("Deadline \(rowDate.text)")
                .font(.meta)
                .foregroundStyle(Today.reason(for: task, at: date) == .overdue ? Palette.urgent : Palette.muted)
        }
    }
}

/// The last row when the rest does not fit: "+N more".
private struct MoreRow: View {
    let count: Int

    var body: some View {
        Link(destination: URL(string: "\(AppConstants.urlScheme)://")!) {
            Text("+\(count) more")
                .font(.meta)
                .foregroundStyle(Palette.muted)
                .frame(height: WidgetTaskRow.height, alignment: .leading)
        }
    }
}

/// A widget title with an optional muted detail and the add button.
private struct WidgetHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if let detail {
                Text(detail)
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Link(destination: URL(string: "\(AppConstants.urlScheme)://tasks/new")!) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 24, height: 24)
                    .background(Palette.ink, in: Circle())
            }
            .accessibilityLabel("Add a task")
        }
        .padding(.bottom, 4)
    }
}
