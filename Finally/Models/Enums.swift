import SwiftUI

// MARK: - TaskStatus

enum TaskStatus: String, Codable, CaseIterable {
    case notStarted = "Not started"
    case inProgress = "In progress"
    case done = "Complete"

    /// Map from Notion status group name to TaskStatus
    static func fromNotionGroup(_ group: String) -> TaskStatus? {
        switch group.lowercased() {
        case "to-do", "to do": return .notStarted
        case "in progress": return .inProgress
        case "complete", "completed", "done": return .done
        default: return nil
        }
    }

    /// Map from Notion status option name to TaskStatus
    static func fromNotionOption(_ name: String) -> TaskStatus? {
        switch name.lowercased() {
        case "not started", "not_started", "to do", "todo": return .notStarted
        case "in progress", "in_progress", "doing": return .inProgress
        case "done", "complete", "completed": return .done
        default: return nil
        }
    }
}

// MARK: - TaskPriority

enum TaskPriority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: Color {
        switch self {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    var icon: String {
        switch self {
        case .urgent: return "flag.fill"
        case .high: return "flag.fill"
        case .medium: return "flag.fill"
        case .low: return "flag.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

// MARK: - Notion Color Mapping

enum NotionColor {
    static func swiftUIColor(for notionColor: String) -> Color {
        switch notionColor.lowercased() {
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

// MARK: - Reminder Offset

enum ReminderOffset: String, CaseIterable, Identifiable {
    case atTime = "At time of event"
    case fiveMin = "5 minutes before"
    case fifteenMin = "15 minutes before"
    case thirtyMin = "30 minutes before"
    case oneHour = "1 hour before"
    case oneDay = "1 day before"

    var id: String { rawValue }

    var intervalSeconds: Int {
        switch self {
        case .atTime: return 0
        case .fiveMin: return 300
        case .fifteenMin: return 900
        case .thirtyMin: return 1800
        case .oneHour: return 3600
        case .oneDay: return 86400
        }
    }
}

// MARK: - Reminder Choice (for InlineTaskCreator)

enum ReminderChoice: Equatable, Identifiable {
    case preset(ReminderOffset)
    case custom(Date)

    var id: String {
        switch self {
        case .preset(let offset): return "preset-\(offset.rawValue)"
        case .custom(let date): return "custom-\(Int(date.timeIntervalSince1970))"
        }
    }

    var displayLabel: String {
        switch self {
        case .preset(let offset): return offset.rawValue
        case .custom(let date): return date.formatted(date: .abbreviated, time: .shortened)
        }
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

    /// Compute the next due date from the given date.
    /// For simple presets only — custom rules use RecurrenceRule.nextDueDate.
    func nextDueDate(from date: Date) -> Date? {
        guard self != .none, self != .custom else { return nil }

        let calendar = Calendar.current
        var next = date

        switch self {
        case .none, .custom:
            return nil
        case .daily:
            return advanceUntilFuture(date: next, calendar: calendar, component: .day, value: 1)
        case .weekly:
            return advanceUntilFuture(date: next, calendar: calendar, component: .day, value: 7)
        case .biweekly:
            return advanceUntilFuture(date: next, calendar: calendar, component: .day, value: 14)
        case .everyWeekday:
            // Skip to next weekday
            repeat {
                guard let advanced = calendar.date(byAdding: .day, value: 1, to: next) else { return nil }
                next = advanced
            } while next <= Date() || calendar.isDateInWeekend(next)
            return next
        case .monthly:
            return advanceUntilFuture(date: next, calendar: calendar, component: .month, value: 1)
        case .yearly:
            return advanceUntilFuture(date: next, calendar: calendar, component: .year, value: 1)
        }
    }

    private func advanceUntilFuture(date: Date, calendar: Calendar, component: Calendar.Component, value: Int) -> Date? {
        var next = date
        repeat {
            guard let advanced = calendar.date(byAdding: component, value: value, to: next) else { return nil }
            next = advanced
        } while next <= Date()
        return next
    }
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

    // MARK: - Next Due Date

    func nextDueDate(from date: Date) -> Date? {
        let calendar = Calendar.current

        switch frequency {
        case .daily:
            return advanceByInterval(from: date, component: .day, value: interval)

        case .weekly:
            if weekdays.isEmpty {
                return advanceByInterval(from: date, component: .day, value: 7 * interval)
            }
            return nextWeekdayOccurrence(from: date, calendar: calendar)

        case .monthly:
            switch monthlyMode {
            case .dayOfMonth:
                return advanceByInterval(from: date, component: .month, value: interval)
            case .nthWeekday:
                return nextNthWeekdayOccurrence(from: date, calendar: calendar)
            }

        case .yearly:
            return advanceByInterval(from: date, component: .year, value: interval)
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

    private func advanceByInterval(from date: Date, component: Calendar.Component, value: Int) -> Date? {
        let calendar = Calendar.current
        var next = date
        repeat {
            guard let advanced = calendar.date(byAdding: component, value: value, to: next) else { return nil }
            next = advanced
        } while next <= Date()
        return next
    }

    private func nextWeekdayOccurrence(from date: Date, calendar: Calendar) -> Date? {
        var next = date

        for _ in 0..<(interval * 7 * 4 + 7) { // Search up to ~4 cycles
            guard let candidate = calendar.date(byAdding: .day, value: 1, to: next) else { return nil }
            next = candidate

            let candidateWeekday = calendar.component(.weekday, from: next)

            // For interval > 1, check week distance from start
            if interval > 1 {
                let weekDiff = calendar.dateComponents([.weekOfYear], from: date, to: next).weekOfYear ?? 0
                if weekDiff > 0 && weekDiff % interval != 0 {
                    continue
                }
            }

            if weekdays.contains(candidateWeekday) && next > Date() {
                return next
            }
        }
        return nil
    }

    private func nextNthWeekdayOccurrence(from date: Date, calendar: Calendar) -> Date? {
        var next = date
        for _ in 0..<(interval * 12 + 1) { // Search up to ~12 cycles
            guard let candidate = calendar.date(byAdding: .month, value: interval, to: next) else { return nil }

            // Find the nth weekday in that month
            let year = calendar.component(.year, from: candidate)
            let month = calendar.component(.month, from: candidate)

            if let nthDate = findNthWeekday(ordinal: nthWeekdayOrdinal, weekday: nthWeekdayDay, month: month, year: year, calendar: calendar) {
                if nthDate > Date() {
                    return nthDate
                }
            }
            next = candidate
        }
        return nil
    }

    private func findNthWeekday(ordinal: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday

        if ordinal == -1 {
            // Last occurrence
            components.weekdayOrdinal = -1
        } else {
            components.weekdayOrdinal = ordinal
        }

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
