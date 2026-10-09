import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared Constants (duplicated for widget target)

private let appGroupID = "group.com.kaungzinye.finally"
private let urlScheme = "finally"

// MARK: - Lightweight Task for Widget Display

struct WidgetTask: Codable, Identifiable {
    let providerWorkspaceID: String
    let externalTaskID: String
    let title: String
    let deadline: Date?
    let priorityRaw: String?
    let isComplete: Bool

    var id: String { "\(providerWorkspaceID):\(externalTaskID)" }

    var priorityColor: Color { Palette.priority(named: priorityRaw) }
}

// MARK: - Timeline Entry

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
}

// MARK: - Timeline Provider

struct TaskTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: .now, tasks: [
            WidgetTask(
                providerWorkspaceID: "preview",
                externalTaskID: "1",
                title: "Sample task",
                deadline: .now,
                priorityRaw: "Medium",
                isComplete: false
            ),
            WidgetTask(
                providerWorkspaceID: "preview",
                externalTaskID: "2",
                title: "Another task",
                deadline: .now,
                priorityRaw: nil,
                isComplete: false
            ),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        let tasks = loadTasks()
        completion(TaskEntry(date: .now, tasks: context.isPreview ? placeholder(in: context).tasks : tasks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let tasks = loadTasks()
        let entry = TaskEntry(date: .now, tasks: tasks)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadTasks() -> [WidgetTask] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "taskPresentationSummaries") else { return [] }
        return (try? JSONDecoder().decode([WidgetTask].self, from: data)) ?? []
    }
}

// MARK: - Widget Views

/// One task: the priority ring, the title, and the deadline when there is room for it.
private struct WidgetTaskRow: View {
    let task: WidgetTask
    var showsDeadline = true

    var body: some View {
        HStack(spacing: 8) {
            PriorityRing(color: task.priorityColor, isDone: task.isComplete, diameter: 14)
            Text(task.title)
                .font(.subheadline)
                .foregroundStyle(task.isComplete ? Palette.muted : Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsDeadline, let deadline = task.deadline {
                Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.medium))
                    .fontDesign(.rounded)
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

/// The widget frame: an eyebrow, the rows, and the add button in the bottom-right corner.
private struct WidgetTaskList: View {
    let entry: TaskEntry
    let limit: Int
    var showsDeadline = true
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TASKS")
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .kerning(0.5)
                .foregroundStyle(Palette.muted)

            if entry.tasks.isEmpty {
                Spacer()
                Text(emptyMessage)
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    WidgetTaskRow(task: task, showsDeadline: showsDeadline)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Link(destination: URL(string: "\(urlScheme)://tasks/new")!) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 32, height: 32)
                        .background(Palette.ink, in: Circle())
                }
            }
        }
    }
}

struct SmallWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        WidgetTaskList(entry: entry, limit: 3, showsDeadline: false, emptyMessage: "No tasks")
    }
}

struct MediumWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        WidgetTaskList(entry: entry, limit: 4, emptyMessage: "No upcoming deadlines")
    }
}

struct LargeWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        WidgetTaskList(entry: entry, limit: 9, emptyMessage: "All caught up")
    }
}

// MARK: - Widget Definition

@main
struct TaskListWidget: Widget {
    let kind = "TaskListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(Palette.paper, for: .widget)
        }
        .configurationDisplayName("Finally Tasks")
        .description("View and manage your tasks")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View (routes to correct size)

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}
