import Foundation

/// How a task detail card shows a scheduled day or deadline: a large day, a muted detail line
/// with what the large day leaves out, and the words VoiceOver reads.
struct PlanningDateLabel: Equatable {
    let day: String
    let detail: String
    let spoken: String
}

extension PlanningDateLabel {
    /// A day within a week reads as a relative word or weekday, such as "Fri", over its date,
    /// "23 Oct". A day further out reads as its date over its weekday, "Thursday". A day in
    /// another year adds the year to its detail line and spoken date. A timed deadline adds its
    /// time to the detail line, such as "23 Oct · 5 pm", and a 12-hour clock drops the minutes
    /// on the hour.
    init(date: Date, hasTime: Bool, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0

        let relative: String? = switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: nil
        }
        let showsDateAsDay = relative == nil && abs(offset) > 6
        let day = relative ?? (showsDateAsDay
            ? date.formatted(style.day().month(.abbreviated))
            : date.formatted(style.weekday(.abbreviated)))
        let isAnotherYear = calendar.component(.year, from: date) != calendar.component(.year, from: referenceDate)
        let spokenDate = style.weekday(.wide).day().month(.wide)
        let spokenDay = relative ?? date.formatted(isAnotherYear ? spokenDate.year() : spokenDate)
        let dateDetail = switch (showsDateAsDay, isAnotherYear) {
        case (true, false): date.formatted(style.weekday(.wide))
        case (true, true): date.formatted(style.weekday(.wide)) + " · " + date.formatted(style.year())
        case (false, false): date.formatted(style.day().month(.abbreviated))
        case (false, true): date.formatted(style.day().month(.abbreviated).year())
        }

        guard hasTime else {
            self.init(day: day, detail: dateDetail, spoken: spokenDay)
            return
        }
        let usesTwelveHourClock = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? false
        let onTheHour = calendar.component(.minute, from: date) == 0
        let time = date.formatted(usesTwelveHourClock && onTheHour ? style.hour() : style.hour().minute())
        self.init(day: day, detail: dateDetail + " · " + time, spoken: spokenDay + " at " + time)
    }
}
