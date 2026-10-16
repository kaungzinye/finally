import Foundation

struct TaskTitleParseResult {
    var cleanTitle: String
    var scheduledDay: Date?
    var deadline: Date?
    var detectedPriority: TaskPriority?
    var detectedProjectName: String?
    var detectedTags: [String]
}

/// Reads capture text. A bare date phrase ("fri") sets the scheduled day, and the same phrase
/// after "due" or "by" ("due fri") sets the deadline.
struct TaskTitleParser {
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> TaskTitleParseResult {
        var remaining = input
        var detectedPriority: TaskPriority? = nil
        var detectedProjectName: String? = nil
        var detectedTags: [String] = []

        // Extract priority: !!1, !!2, !!3, !!4
        if let match = remaining.range(of: #"!!([1-4])"#, options: .regularExpression) {
            let digit = remaining[match].dropFirst(2)
            switch digit {
            case "1": detectedPriority = .urgent
            case "2": detectedPriority = .high
            case "3": detectedPriority = .medium
            case "4": detectedPriority = .low
            default: break
            }
            remaining.removeSubrange(match)
        }

        // Extract project: @"Multi Word" or @SingleWord
        if let quotedMatch = remaining.range(of: #"@"([^"]+)""#, options: .regularExpression) {
            let full = String(remaining[quotedMatch])
            // Remove @" and trailing "
            let name = String(full.dropFirst(2).dropLast(1))
            detectedProjectName = name
            remaining.removeSubrange(quotedMatch)
        } else if let match = remaining.range(of: #"@(\w+)"#, options: .regularExpression) {
            let name = String(remaining[match].dropFirst(1))
            detectedProjectName = name
            remaining.removeSubrange(match)
        }

        // Extract tags: #tagname (multiple allowed)
        while let match = remaining.range(of: #"#(\w+)"#, options: .regularExpression) {
            let tag = String(remaining[match].dropFirst(1))
            detectedTags.append(tag)
            remaining.removeSubrange(match)
        }

        let today = calendar.startOfDay(for: now)
        let deadline = extractDate(from: &remaining, prefix: #"(?:due|by)\s+"#, today: today, calendar: calendar)
        let scheduledDay = extractDate(from: &remaining, prefix: "", today: today, calendar: calendar)

        // Clean up extra whitespace
        let cleanTitle = remaining
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return TaskTitleParseResult(
            cleanTitle: cleanTitle,
            scheduledDay: scheduledDay,
            deadline: deadline,
            detectedPriority: detectedPriority,
            detectedProjectName: detectedProjectName,
            detectedTags: detectedTags
        )
    }

    // MARK: - Date phrases

    /// A date phrase: a regex and the day its capture groups name, relative to today.
    private struct DatePhrase {
        let pattern: String
        let resolve: (_ groups: [String], _ today: Date, _ calendar: Calendar) -> Date?
    }

    private static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Checked in order. The first phrase found anywhere in the text wins.
    private static let phrases: [DatePhrase] = [
        DatePhrase(pattern: "today") { _, today, _ in today },
        DatePhrase(pattern: "tomorrow") { _, today, calendar in
            calendar.date(byAdding: .day, value: 1, to: today)
        },
        DatePhrase(pattern: "(sunday|monday|tuesday|wednesday|thursday|friday|saturday|sun|mon|tues|tue|wed|thurs|thu|fri|sat)") { groups, today, calendar in
            guard let index = weekdays.firstIndex(of: String(groups[0].lowercased().prefix(3))) else { return nil }
            return nextWeekday(index + 1, from: today, calendar: calendar)
        },
        DatePhrase(pattern: #"next\s+week"#) { _, today, calendar in
            nextWeekday(2, from: today, calendar: calendar)
        },
        DatePhrase(pattern: #"next\s+month"#) { _, today, calendar in
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            return calendar.date(byAdding: .month, value: 1, to: startOfMonth)
        },
        DatePhrase(pattern: #"in\s+(\d+)\s+(day|week|month)s?"#) { groups, today, calendar in
            guard let count = Int(groups[0]) else { return nil }
            switch groups[1].lowercased() {
            case "day": return calendar.date(byAdding: .day, value: count, to: today)
            case "week": return calendar.date(byAdding: .day, value: count * 7, to: today)
            default: return calendar.date(byAdding: .month, value: count, to: today)
            }
        },
        DatePhrase(pattern: #"(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\s+(\d{1,2})"#) { groups, today, calendar in
            guard let month = months.firstIndex(of: String(groups[0].lowercased().prefix(3))), let day = Int(groups[1]) else { return nil }
            return nextOccurrence(month: month + 1, day: day, onOrAfter: today, calendar: calendar)
        },
        DatePhrase(pattern: #"(\d{1,2})/(\d{1,2})"#) { groups, today, calendar in
            guard let month = Int(groups[0]), let day = Int(groups[1]) else { return nil }
            return nextOccurrence(month: month, day: day, onOrAfter: today, calendar: calendar)
        },
    ]

    /// Removes the first date phrase that follows `prefix` and returns its day.
    private static func extractDate(from text: inout String, prefix: String, today: Date, calendar: Calendar) -> Date? {
        for phrase in phrases {
            let regex = try! NSRegularExpression(pattern: #"\b"# + prefix + "(?:" + phrase.pattern + #")\b"#, options: .caseInsensitive)
            let whole = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: whole) {
                let groups = (1..<match.numberOfRanges).compactMap { index in
                    Range(match.range(at: index), in: text).map { String(text[$0]) }
                }
                guard let date = phrase.resolve(groups, today, calendar),
                      let range = Range(match.range, in: text) else { continue }
                text.removeSubrange(range)
                return date
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func nextWeekday(_ weekday: Int, from date: Date, calendar: Calendar) -> Date {
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysAhead = weekday - currentWeekday
        if daysAhead <= 0 { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: date)!
    }

    /// The next real calendar day with this month and day, this year or next.
    private static func nextOccurrence(month: Int, day: Int, onOrAfter today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        for candidateYear in [year, year + 1] {
            let components = DateComponents(year: candidateYear, month: month, day: day)
            guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { continue }
            if date >= today { return date }
        }
        return nil
    }
}
