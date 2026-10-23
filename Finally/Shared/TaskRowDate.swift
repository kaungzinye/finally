import Foundation

/// The one date a task row shows: the deadline when the task has one, otherwise its scheduled day.
/// A scheduled day that has passed reads "from Sat". A date in another year carries its year.
/// `text` reads in full on one line, for VoiceOver and roomier layouts. The row's narrow date
/// column shows a compact form: `columnDay` such as "Tmr", "Fri", "23 Oct", or "Oct '27", and
/// `columnDetail` on a second line, holding a deadline's time or the day a missed scheduled day
/// runs "from".
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

    /// The date in words under a Daily Focus pick's title, such as "Today", "from Wed", or
    /// "Deadline Fri 5:00 PM".
    var sentence: String {
        guard kind == .deadline else { return text }
        let relative = ["Today", "Tomorrow", "Yesterday"].first { text.hasPrefix($0) }
        return "Deadline " + (relative.map { $0.lowercased() + text.dropFirst($0.count) } ?? text)
    }
}

extension TaskRowDate {
    init?(for task: some TodayTask, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        func days(to date: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        }
        /// The day in full and in its compact column form.
        func day(_ date: Date) -> (text: String, compact: String) {
            switch days(to: date) {
            case 0: ("Today", "Today")
            case 1: ("Tomorrow", "Tmr")
            case -1: ("Yesterday", "Yest")
            case 2...6: (date.formatted(style.weekday(.abbreviated)), date.formatted(style.weekday(.abbreviated)))
            default: (DayMonth.text(for: date, at: referenceDate, calendar: calendar, locale: locale),
                      DayMonth.compact(for: date, at: referenceDate, calendar: calendar, locale: locale))
            }
        }

        if let deadline = task.deadline {
            let day = day(deadline)
            guard task.deadlineHasTime else {
                self.init(kind: .deadline, text: day.text, columnDay: day.compact)
                return
            }
            let time = deadline.formatted(style.hour().minute())
            self.init(kind: .deadline, text: day.text + " " + time, columnDay: day.compact, columnDetail: time)
        } else if let scheduledDay = task.scheduledDay {
            switch days(to: scheduledDay) {
            case ..<(-6):
                let text = DayMonth.text(for: scheduledDay, at: referenceDate, calendar: calendar, locale: locale)
                let compact = DayMonth.compact(for: scheduledDay, at: referenceDate, calendar: calendar, locale: locale)
                self.init(kind: .scheduledDay, text: "from " + text, columnDay: "from", columnDetail: compact)
            case ..<0:
                let weekday = scheduledDay.formatted(style.weekday(.abbreviated))
                self.init(kind: .scheduledDay, text: "from " + weekday, columnDay: "from", columnDetail: weekday)
            default:
                let day = day(scheduledDay)
                self.init(kind: .scheduledDay, text: day.text, columnDay: day.compact)
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

    /// The date in a row's narrow date column: the day and month, such as "23 Oct", or the month
    /// and a two-digit year, such as "Oct '27", when the year differs from the reference date's.
    static func compact(for date: Date, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        guard calendar.component(.year, from: date) != calendar.component(.year, from: referenceDate) else {
            return date.formatted(style.month(.abbreviated).day())
        }
        let year = calendar.component(.year, from: date) % 100
        return date.formatted(style.month(.abbreviated)) + " '" + String(format: "%02d", year)
    }
}
