import Foundation

/// The one date a task row shows: the deadline when the task has one, otherwise its scheduled day.
/// A scheduled day that has passed reads "from Sat". A date in another year carries its year.
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
            default: DayMonth.text(for: date, at: referenceDate, calendar: calendar, locale: locale)
            }
        }

        if let deadline = task.deadline {
            let time = task.deadlineHasTime ? " " + deadline.formatted(style.hour().minute()) : ""
            self.init(kind: .deadline, text: day(deadline) + time)
        } else if let scheduledDay = task.scheduledDay {
            let offset = days(to: scheduledDay)
            switch offset {
            case ..<(-6): self.init(kind: .scheduledDay, text: "from " + DayMonth.text(for: scheduledDay, at: referenceDate, calendar: calendar, locale: locale))
            case ..<0: self.init(kind: .scheduledDay, text: "from " + scheduledDay.formatted(style.weekday(.abbreviated)))
            default: self.init(kind: .scheduledDay, text: day(scheduledDay))
            }
        } else {
            return nil
        }
    }
}

/// A date as its day and month, such as "20 Oct", with the year added when it differs from the
/// reference date's year, such as "20 Oct 2027".
enum DayMonth {
    static func text(for date: Date, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        let isAnotherYear = calendar.component(.year, from: date) != calendar.component(.year, from: referenceDate)
        return date.formatted(isAnotherYear ? style.year() : style)
    }
}
