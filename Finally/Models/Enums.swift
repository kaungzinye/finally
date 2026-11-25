import SwiftUI

// MARK: - Tag Color Mapping

enum TaskTagColor {
    static func swiftUIColor(for colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "brown": return .brown
        case "gray", "grey": return .gray
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        default: return .secondary
        }
    }
}

// MARK: - Multi-Level Sort

enum SortField: String, Codable, CaseIterable, Identifiable {
    case priority = "Priority"
    case title = "Title"
    case status = "Status"
    case project = "Project"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .priority: return "flag"
        case .title: return "textformat"
        case .status: return "circle.dotted"
        case .project: return "folder"
        }
    }
}

struct SortCriterion: Codable, Identifiable, Equatable {
    let id: UUID
    var field: SortField
    var ascending: Bool

    init(field: SortField, ascending: Bool = true) {
        self.id = UUID()
        self.field = field
        self.ascending = ascending
    }
}

struct SortStack: Codable, Equatable {
    var criteria: [SortCriterion]

    static let `default` = SortStack(criteria: [
        SortCriterion(field: .priority, ascending: true)
    ])

    func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            for criterion in criteria {
                let result = compareField(criterion.field, a, b)
                if result != .orderedSame {
                    return criterion.ascending
                        ? result == .orderedAscending
                        : result == .orderedDescending
                }
            }
            return false
        }
    }

    private func compareField(_ field: SortField, _ a: TaskItem, _ b: TaskItem) -> ComparisonResult {
        switch field {
        case .priority:
            let aVal = a.priority?.sortOrder ?? 99
            let bVal = b.priority?.sortOrder ?? 99
            if aVal < bVal { return .orderedAscending }
            if aVal > bVal { return .orderedDescending }
            return .orderedSame
        case .title:
            return a.title.localizedCompare(b.title)
        case .status:
            let order: [TaskStatus] = [.notStarted, .inProgress, .done]
            let aIdx = order.firstIndex(of: a.status) ?? 0
            let bIdx = order.firstIndex(of: b.status) ?? 0
            if aIdx < bIdx { return .orderedAscending }
            if aIdx > bIdx { return .orderedDescending }
            return .orderedSame
        case .project:
            let aName = a.project?.title ?? ""
            let bName = b.project?.title ?? ""
            return aName.localizedCompare(bName)
        }
    }

    var jsonString: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{}"
    }

    static func from(_ json: String) -> SortStack {
        guard let data = json.data(using: .utf8),
              let stack = try? JSONDecoder().decode(SortStack.self, from: data) else {
            return .default
        }
        return stack
    }
}

// MARK: - Recurrence

enum Recurrence: String, Codable, CaseIterable {
    case none = "None"
    case daily = "Daily"
    case weekly = "Weekly"
    case everyWeekday = "Every weekday"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case custom = "Custom"

    /// Cases shown in the quick-preset list (excludes .custom since it's handled separately)
    static var presetCases: [Recurrence] {
        [.none, .daily, .weekly, .everyWeekday, .biweekly, .monthly, .yearly]
    }

    var icon: String {
        switch self {
        case .none: return "arrow.counterclockwise"
        default: return "repeat"
        }
    }

    /// Compute the next deadline from the given date.
    /// For simple presets only — custom rules use RecurrenceRule.nextDeadline.
    func nextDeadline(from date: Date, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard self != .none, self != .custom else { return nil }

        switch self {
        case .none, .custom:
            return nil
        case .daily:
            return nextDate(from: date, after: now, calendar: calendar, component: .day, value: 1)
        case .weekly:
            return nextDate(from: date, after: now, calendar: calendar, component: .day, value: 7)
        case .biweekly:
            return nextDate(from: date, after: now, calendar: calendar, component: .day, value: 14)
        case .everyWeekday:
            var days = 1
            while let next = calendar.date(byAdding: .day, value: days, to: date) {
                if next > now, !calendar.isDateInWeekend(next) { return next }
                days += 1
            }
            return nil
        case .monthly:
            return nextDate(from: date, after: now, calendar: calendar, component: .month, value: 1)
        case .yearly:
            return nextDate(from: date, after: now, calendar: calendar, component: .year, value: 1)
        }
    }
}

/// The first date in a repeating pattern after both `date` and `now`. Every step counts from
/// `date`, so a short month or a clock change skipped on the way leaves later dates alone.
private func nextDate(from date: Date, after now: Date, calendar: Calendar, component: Calendar.Component, value: Int) -> Date? {
    var step = 1
    while let next = calendar.date(byAdding: component, value: value * step, to: date) {
        if next > now { return next }
        step += 1
    }
    return nil
}

// MARK: - RecurrenceRule (Google Calendar-style advanced patterns)

struct RecurrenceRule: Codable, Equatable {
    enum Frequency: String, Codable, CaseIterable {
        case daily = "day"
        case weekly = "week"
        case monthly = "month"
        case yearly = "year"

        var pluralLabel: String {
            switch self {
            case .daily: return "days"
            case .weekly: return "weeks"
            case .monthly: return "months"
            case .yearly: return "years"
            }
        }

        var singularLabel: String { rawValue }
    }

    enum MonthlyMode: String, Codable {
        case dayOfMonth    // e.g., "on day 15"
        case nthWeekday    // e.g., "on the 2nd Tuesday"
    }

    var frequency: Frequency = .weekly
    var interval: Int = 1                   // Every N ...
    var weekdays: Set<Int> = []             // 1=Sun, 2=Mon, ..., 7=Sat (used when frequency == .weekly)
    var monthlyMode: MonthlyMode = .dayOfMonth
    var nthWeekdayOrdinal: Int = 1          // 1st, 2nd, 3rd, 4th, or -1 for last (monthly nthWeekday mode)
    var nthWeekdayDay: Int = 2              // 1=Sun..7=Sat (monthly nthWeekday mode)

    // MARK: - Summary

    var summary: String {
        var parts: [String] = []

        if interval == 1 {
            parts.append("Every \(frequency.singularLabel)")
        } else {
            parts.append("Every \(interval) \(frequency.pluralLabel)")
        }

        if frequency == .weekly && !weekdays.isEmpty {
            let dayNames = weekdays.sorted().compactMap { Self.shortDayName($0) }
            parts.append("on \(dayNames.joined(separator: ", "))")
        }

        if frequency == .monthly && monthlyMode == .nthWeekday {
            let ordinal = Self.ordinalName(nthWeekdayOrdinal)
            let day = Self.fullDayName(nthWeekdayDay)
            parts.append("on the \(ordinal) \(day)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Next Deadline

    func nextDeadline(from date: Date, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch frequency {
        case .daily:
            return nextDate(from: date, after: now, calendar: calendar, component: .day, value: interval)

        case .weekly:
            if weekdays.isEmpty {
                return nextDate(from: date, after: now, calendar: calendar, component: .day, value: 7 * interval)
            }
            return nextWeekdayOccurrence(from: date, after: now, calendar: calendar)

        case .monthly:
            switch monthlyMode {
            case .dayOfMonth:
                return nextDate(from: date, after: now, calendar: calendar, component: .month, value: interval)
            case .nthWeekday:
                return nextNthWeekdayOccurrence(from: date, after: now, calendar: calendar)
            }

        case .yearly:
            return nextDate(from: date, after: now, calendar: calendar, component: .year, value: interval)
        }
    }

    // MARK: - JSON

    var jsonString: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{}"
    }

    static func from(_ json: String?) -> RecurrenceRule? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
    }

    // MARK: - Helpers

    private func nextWeekdayOccurrence(from date: Date, after now: Date, calendar: Calendar) -> Date? {
        // Search past today, then far enough for one full interval.
        let daysLate = max(calendar.dateComponents([.day], from: date, to: now).day ?? 0, 0)
        for days in 1...(daysLate + interval * 14 + 7) {
            guard let next = calendar.date(byAdding: .day, value: days, to: date) else { return nil }

            let candidateWeekday = calendar.component(.weekday, from: next)

            // Every other week counts calendar weeks from the deadline's own week, which is
            // always one the rule selects.
            if interval > 1 {
                guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
                      let week = calendar.dateInterval(of: .weekOfYear, for: next)?.start else { return nil }
                let weeksApart = (calendar.dateComponents([.day], from: firstWeek, to: week).day ?? 0) / 7
                if weeksApart % interval != 0 { continue }
            }

            if weekdays.contains(candidateWeekday) && next > now {
                return next
            }
        }
        return nil
    }

    private func nextNthWeekdayOccurrence(from date: Date, after now: Date, calendar: Calendar) -> Date? {
        let monthsLate = max(calendar.dateComponents([.month], from: date, to: now).month ?? 0, 0)
        for step in 1...(monthsLate / max(interval, 1) + 400) {
            guard let candidate = calendar.date(byAdding: .month, value: interval * step, to: date) else { return nil }

            // Find the nth weekday in that month
            let year = calendar.component(.year, from: candidate)
            let month = calendar.component(.month, from: candidate)

            if let nthDate = findNthWeekday(ordinal: nthWeekdayOrdinal, weekday: nthWeekdayDay, month: month, year: year, timeOf: date, calendar: calendar) {
                if nthDate > now {
                    return nthDate
                }
            }
        }
        return nil
    }

    private func findNthWeekday(ordinal: Int, weekday: Int, month: Int, year: Int, timeOf date: Date, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        let firstMatch = 1 + (weekday - calendar.component(.weekday, from: first) + 7) % 7
        let day = ordinal == -1
            ? firstMatch + (daysInMonth - firstMatch) / 7 * 7
            : firstMatch + (ordinal - 1) * 7
        // A month without a fifth one is skipped.
        guard day <= daysInMonth else { return nil }
        var components = calendar.dateComponents([.hour, .minute, .second], from: date)
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    static func shortDayName(_ weekday: Int) -> String? {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard weekday >= 1 && weekday <= 7 else { return nil }
        return names[weekday]
    }

    static func fullDayName(_ weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard weekday >= 1 && weekday <= 7 else { return "Monday" }
        return names[weekday]
    }

    static func ordinalName(_ n: Int) -> String {
        switch n {
        case -1: return "last"
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "\(n)th"
        }
    }

    /// Build a default rule from the current date context
    static func defaultForDate(_ date: Date?) -> RecurrenceRule {
        let calendar = Calendar.current
        var rule = RecurrenceRule()

        if let date {
            let weekday = calendar.component(.weekday, from: date)
            rule.weekdays = [weekday]
            rule.nthWeekdayOrdinal = calendar.component(.weekdayOrdinal, from: date)
            rule.nthWeekdayDay = weekday
        }

        return rule
    }
}
