import Foundation

/// The one date a task row shows: the deadline when the task has one, otherwise its scheduled day.
/// A scheduled day that has passed reads "from Sat".
struct TaskRowDate: Equatable {
    enum Kind: Equatable {
        case deadline
        case scheduledDay
    }

    let kind: Kind
    let text: String
}

extension TaskRowDate {
    init?(for task: some TodayTask, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        func days(to date: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        }
        func day(_ date: Date) -> String {
            switch days(to: date) {
            case 0: "Today"
            case 1: "Tomorrow"
            case -1: "Yesterday"
            case 2...6: date.formatted(style.weekday(.abbreviated))
            default: date.formatted(style.month(.abbreviated).day())
            }
        }

        if let deadline = task.deadline {
            let time = task.deadlineHasTime ? " " + deadline.formatted(style.hour().minute()) : ""
            self.init(kind: .deadline, text: day(deadline) + time)
        } else if let scheduledDay = task.scheduledDay {
            let offset = days(to: scheduledDay)
            switch offset {
            case ..<(-6): self.init(kind: .scheduledDay, text: "from " + scheduledDay.formatted(style.month(.abbreviated).day()))
            case ..<0: self.init(kind: .scheduledDay, text: "from " + scheduledDay.formatted(style.weekday(.abbreviated)))
            default: self.init(kind: .scheduledDay, text: day(scheduledDay))
            }
        } else {
            return nil
        }
    }
}
