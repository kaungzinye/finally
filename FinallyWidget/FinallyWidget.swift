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

/// Reads the snapshot the app writes, with the widget completions the app has yet to apply. The timeline adds an entry after each timed deadline left
/// today and at the next midnight, so deadlines turn overdue and Today rolls over without the app.
struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(snapshot: .sample(at: .now), at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let snapshot = context.isPreview ? .sample(at: .now) : storedSnapshot
        completion(DayEntry(snapshot: snapshot, at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = storedSnapshot
        completion(Timeline(
            entries: snapshot.timelineDates(from: Date()).map { DayEntry(snapshot: snapshot, at: $0) },
            policy: .atEnd
        ))
    }

    private var storedSnapshot: WidgetSnapshot {
        WidgetStorage.appGroup?.displayedSnapshot ?? .empty
    }
}

@main
struct FinallyWidgets: WidgetBundle {
    var body: some Widget {
        FocusWidget()
        NowWidget()
        TodayWidget()
        TodayRingWidget()
    }
}

/// "3 things to do": the open Daily Focus picks.
struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.focus, provider: DayProvider()) { entry in
            FocusWidgetView(day: entry.day, date: entry.date)
                .containerBackground(Palette.paper, for: .widget)
        }
        .configurationDisplayName("3 things to do")
        .description("Your Daily Focus, with a ring to finish each pick.")
        .supportedFamilies([.systemMedium])
    }
}

/// "Next up": the first open Daily Focus pick.
struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.now, provider: DayProvider()) { entry in
            NowWidgetView(day: entry.day, date: entry.date)
                .containerBackground(Palette.paper, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("The next task in your Daily Focus.")
        .supportedFamilies([.systemSmall])
    }
}

/// "Today": all of Today, then the days coming up.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.today, provider: DayProvider()) { entry in
            TodayWidgetView(day: entry.day, date: entry.date)
                .containerBackground(Palette.paper, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Everything on today's plate, then the week ahead.")
        .supportedFamilies([.systemLarge])
    }
}

/// "Today ring": the lock screen ring and the lock screen next pick.
struct TodayRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.todayRing, provider: DayProvider()) { entry in
            TodayRingEntryView(entry: entry)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Today ring")
        .description("Today's progress on the lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

/// Routes each lock screen family to its view: the ring, or the next pick.
struct TodayRingEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockScreenNowView(day: entry.day, date: entry.date)
        default:
            LockScreenRingView(day: entry.day)
        }
    }
}

extension WidgetSnapshot {
    static let empty = WidgetSnapshot(workspaceID: "", focusDay: nil, focusLimit: AppConstants.defaultFocusLimit, focusPickCount: 0, isFocusConfirmed: false, tasks: [])

    /// What the widget gallery shows.
    static func sample(at date: Date) -> WidgetSnapshot {
        let today = Calendar.current.startOfDay(for: date)
        func task(
            _ title: String,
            priority: TaskPriority? = nil,
            deadline: Date? = nil,
            status: TaskStatus = .notStarted
        ) -> WidgetTask {
            WidgetTask(
                providerWorkspaceID: "sample", externalTaskID: title, title: title, priority: priority,
                status: status, scheduledDay: today, deadline: deadline
            )
        }
        let picks = ["Draft the brief", "Call the bank", "Review the contract"].enumerated().map {
            WidgetFocusPlace(position: $0.offset + 1, taskIDs: ["sample:\($0.element)"])
        }
        return WidgetSnapshot(workspaceID: "sample", focusDay: today, focusLimit: 3, focusPickCount: 3, isFocusConfirmed: true, focusPlaces: picks, tasks: [
            task("Draft the brief", priority: .high, deadline: today, status: .done),
            task("Call the bank", priority: .medium),
            task("Review the contract"),
            task("Send the invoice", priority: .medium, deadline: today),
            task("Water the plants"),
        ])
    }
}
