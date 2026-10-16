import SwiftUI
import WidgetKit

/// One moment of the widget timeline: the day as the widgets draw it at that moment.
struct DayEntry: TimelineEntry {
    let date: Date
    let day: WidgetDay

    init(snapshot: WidgetSnapshot, at date: Date) {
        self.date = date
        day = WidgetDay(snapshot: snapshot, at: date)
    }
}

/// Reads the snapshot the app writes. The timeline adds an entry at the next midnight so Today
/// rolls over without the app.
struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(snapshot: .sample(at: .now), at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let snapshot = context.isPreview ? .sample(at: .now) : storedSnapshot
        completion(DayEntry(snapshot: snapshot, at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let snapshot = storedSnapshot
        completion(Timeline(
            entries: [DayEntry(snapshot: snapshot, at: now), DayEntry(snapshot: snapshot, at: midnight)],
            policy: .atEnd
        ))
    }

    private var storedSnapshot: WidgetSnapshot {
        WidgetStorage.appGroup?.snapshot ?? .empty
    }
}

@main
struct FinallyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKind, provider: DayProvider()) { entry in
            FinallyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your Daily Focus and the rest of Today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

/// Routes each family to its widget: now, focus, today, the lock screen ring, and lock screen now.
struct FinallyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        switch family {
        case .systemSmall:
            NowWidgetView(day: entry.day, date: entry.date)
                .containerBackground(Palette.paper, for: .widget)
        case .systemLarge:
            TodayWidgetView(day: entry.day, date: entry.date)
                .containerBackground(Palette.paper, for: .widget)
        case .accessoryCircular:
            LockScreenRingView(day: entry.day)
                .containerBackground(Color.clear, for: .widget)
        case .accessoryRectangular:
            LockScreenNowView(day: entry.day, date: entry.date)
                .containerBackground(Color.clear, for: .widget)
        default:
            FocusWidgetView(day: entry.day, date: entry.date)
                .containerBackground(Palette.paper, for: .widget)
        }
    }
}

extension WidgetSnapshot {
    static let empty = WidgetSnapshot(workspaceID: "", focusDay: nil, focusLimit: AppConstants.defaultFocusLimit, focusPickCount: 0, tasks: [])

    /// What the widget gallery shows.
    static func sample(at date: Date) -> WidgetSnapshot {
        let today = Calendar.current.startOfDay(for: date)
        func task(
            _ title: String,
            priority: TaskPriority? = nil,
            deadline: Date? = nil,
            status: TaskStatus = .notStarted,
            focusPosition: Int? = nil
        ) -> WidgetTask {
            WidgetTask(
                providerWorkspaceID: "sample", externalTaskID: title, title: title, priority: priority,
                status: status, scheduledDay: today, deadline: deadline, focusPosition: focusPosition
            )
        }
        return WidgetSnapshot(workspaceID: "sample", focusDay: today, focusLimit: 3, focusPickCount: 3, tasks: [
            task("Draft the brief", priority: .high, deadline: today, status: .done, focusPosition: 1),
            task("Call the bank", priority: .medium, focusPosition: 2),
            task("Review the contract", focusPosition: 3),
            task("Send the invoice", priority: .medium, deadline: today),
            task("Water the plants"),
        ])
    }
}
