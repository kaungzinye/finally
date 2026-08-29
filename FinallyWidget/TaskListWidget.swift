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

    var priorityColor: Color {
        switch priorityRaw {
        case "Urgent": return .red
        case "High": return .orange
        case "Medium": return .yellow
        default: return .clear
        }
    }
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

struct SmallWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entry.tasks.isEmpty {
                Spacer()
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(entry.tasks.prefix(3)) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(task.isComplete ? .green : .secondary)
                        Text(task.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Link(destination: URL(string: "\(urlScheme)://tasks/new")!) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding()
    }
}

struct MediumWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entry.tasks.isEmpty {
                Spacer()
                Text("No upcoming deadlines")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(entry.tasks.prefix(5)) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(task.isComplete ? .green : .secondary)
                        Text(task.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let deadline = task.deadline {
                            Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Link(destination: URL(string: "\(urlScheme)://tasks/new")!) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding()
    }
}

struct LargeWidgetView: View {
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entry.tasks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("All caught up!")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(9)) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(task.isComplete ? .green : .secondary)

                        if task.priorityColor != .clear {
                            Circle()
                                .fill(task.priorityColor)
                                .frame(width: 6, height: 6)
                        }

                        Text(task.title)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        if let deadline = task.deadline {
                            Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Link(destination: URL(string: "\(urlScheme)://tasks/new")!) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget Definition

@main
struct TaskListWidget: Widget {
    let kind = "TaskListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
