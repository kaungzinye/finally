import Foundation

/// The one date a task row shows: the deadline when the task has one, otherwise its scheduled day.
/// A scheduled day that has passed reads "from Sat". A date in another year carries its year.
/// `text` reads on one line, and the row's narrow date column splits it into the day and a
/// second line holding the year or time.
struct TaskRowDate: Equatable {
    enum Kind: Equatable {
        case deadline
        case scheduledDay
    }

    let kind: Kind
    let text: String
    let columnDay: String
    let columnDetail: String?

    init(kind: Kind, text: String, columnDay: String? = nil, columnDetail: String? = nil) {
        self.kind = kind
        self.text = text
        self.columnDay = columnDay ?? text
        self.columnDetail = columnDetail
    }
}

extension TaskRowDate {
    init?(for task: some TodayTask, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        func days(to date: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        }
        func isAnotherYear(_ date: Date) -> Bool {
            calendar.component(.year, from: date) != calendar.component(.year, from: referenceDate)
        }
        /// The date as a day and month, with its year apart when the year differs from today's.
        func dayMonth(_ date: Date) -> (text: String, day: String, year: String?) {
            let text = DayMonth.text(for: date, at: referenceDate, calendar: calendar, locale: locale)
            let day = date.formatted(style.month(.abbreviated).day())
            return (text, day, isAnotherYear(date) ? date.formatted(style.year()) : nil)
        }
        func day(_ date: Date) -> (text: String, day: String, year: String?) {
            switch days(to: date) {
            case 0: ("Today", "Today", nil)
            case 1: ("Tomorrow", "Tomorrow", nil)
            case -1: ("Yesterday", "Yesterday", nil)
            case 2...6: (date.formatted(style.weekday(.abbreviated)), date.formatted(style.weekday(.abbreviated)), nil)
            default: dayMonth(date)
            }
        }

        if let deadline = task.deadline {
            let day = day(deadline)
            guard task.deadlineHasTime else {
                self.init(kind: .deadline, text: day.text, columnDay: day.day, columnDetail: day.year)
                return
            }
            let time = deadline.formatted(style.hour().minute())
            self.init(kind: .deadline, text: day.text + " " + time, columnDay: day.day, columnDetail: day.year.map { $0 + " " + time } ?? time)
        } else if let scheduledDay = task.scheduledDay {
            switch days(to: scheduledDay) {
            case ..<(-6):
                let date = dayMonth(scheduledDay)
                self.init(kind: .scheduledDay, text: "from " + date.text, columnDay: "from " + date.day, columnDetail: date.year)
            case ..<0:
                self.init(kind: .scheduledDay, text: "from " + scheduledDay.formatted(style.weekday(.abbreviated)))
            default:
                let day = day(scheduledDay)
                self.init(kind: .scheduledDay, text: day.text, columnDay: day.day, columnDetail: day.year)
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
