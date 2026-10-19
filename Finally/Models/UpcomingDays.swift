import Foundation

/// Upcoming's days for one workspace. An open top-level task sits on the earlier of its scheduled
/// day and deadline still ahead, so a task with both dates appears once. A scheduled day takes
/// tomorrow onwards, because today's belongs to Today. A deadline takes any moment from now on.
struct UpcomingDays {
    struct Day: Identifiable {
        let day: Date
        let tasks: [TaskItem]

        var id: Date { day }
    }

    let days: [Day]

    init(tasks: [TaskItem], workspace: UserSession?, at referenceDate: Date = Date(), calendar: Calendar = .current) {
        let grouped = Dictionary(grouping: tasks.compactMap { task -> (Date, TaskItem)? in
            guard task.belongs(to: workspace), !task.isDeleted, task.status != .done, !task.isSubtask,
                  let date = Self.date(of: task, after: referenceDate) else { return nil }
            return (calendar.startOfDay(for: date), task)
        }) { $0.0 }
        days = grouped.keys.sorted().map { day in
            Day(day: day, tasks: grouped[day]?.map(\.1) ?? [])
        }
    }

    private static func date(of task: TaskItem, after referenceDate: Date) -> Date? {
        [task.scheduledDay, task.deadline]
            .compactMap { $0 }
            .filter { $0 > referenceDate }
            .min()
    }
}
