import Foundation

/// How a task detail card shows a scheduled day or deadline: a large relative day, a muted
/// detail line with the full date, and the words VoiceOver reads.
struct PlanningDateLabel: Equatable {
    let day: String
    let detail: String
    let spoken: String
}

extension PlanningDateLabel {
    /// A timed deadline's detail line drops the weekday to make room for its time, such as
    /// "23 Oct · 5 pm". A 12-hour clock drops the minutes on the hour.
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
        let day = relative ?? (abs(offset) <= 6
            ? date.formatted(style.weekday(.abbreviated))
            : date.formatted(style.day().month(.abbreviated)))
        let spokenDay = relative ?? date.formatted(style.weekday(.wide).day().month(.wide))

        guard hasTime else {
            self.init(day: day, detail: date.formatted(style.weekday(.abbreviated).day().month(.abbreviated)), spoken: spokenDay)
            return
        }
        let usesTwelveHourClock = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? false
        let onTheHour = calendar.component(.minute, from: date) == 0
        let time = date.formatted(usesTwelveHourClock && onTheHour ? style.hour() : style.hour().minute())
        self.init(
            day: day,
            detail: date.formatted(style.day().month(.abbreviated)) + " · " + time,
            spoken: spokenDay + " at " + time
        )
    }
}
