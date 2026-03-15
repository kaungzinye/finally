import Foundation

struct TaskTitleParseResult {
    var cleanTitle: String
    var detectedDate: Date?
    var detectedPriority: TaskPriority?
    var detectedProjectName: String?
    var detectedTags: [String]
}

struct TaskTitleParser {
    static func parse(_ input: String) -> TaskTitleParseResult {
        var remaining = input
        var detectedDate: Date? = nil
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

        // Extract date keywords (case-insensitive)
        detectedDate = extractDate(from: &remaining)

        // Clean up extra whitespace
        let cleanTitle = remaining
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return TaskTitleParseResult(
            cleanTitle: cleanTitle,
            detectedDate: detectedDate,
            detectedPriority: detectedPriority,
            detectedProjectName: detectedProjectName,
            detectedTags: detectedTags
        )
    }

    // MARK: - Date Extraction

    private static func extractDate(from text: inout String) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // "today"
        if let range = matchWord(in: text, word: "today") {
            text.removeSubrange(range)
            return today
        }

        // "tomorrow"
        if let range = matchWord(in: text, word: "tomorrow") {
            text.removeSubrange(range)
            return calendar.date(byAdding: .day, value: 1, to: today)
        }

        // "yesterday"
        if let range = matchWord(in: text, word: "yesterday") {
            text.removeSubrange(range)
            return calendar.date(byAdding: .day, value: -1, to: today)
        }

        // Day names: "monday" through "sunday"
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (index, dayName) in dayNames.enumerated() {
            if let range = matchWord(in: text, word: dayName) {
                text.removeSubrange(range)
                return nextWeekday(index + 1, from: today)
            }
            // Also check abbreviated: "mon", "tue", "wed", "thu", "fri", "sat", "sun"
            let abbrevs = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            if let range = matchWord(in: text, word: abbrevs[index]) {
                text.removeSubrange(range)
                return nextWeekday(index + 1, from: today)
            }
        }

        // "next week" → next Monday
        if let range = matchPhrase(in: text, phrase: "next week") {
            text.removeSubrange(range)
            return nextWeekday(2, from: today) // Monday
        }

        // "next month" → 1st of next month
        if let range = matchPhrase(in: text, phrase: "next month") {
            text.removeSubrange(range)
            return calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: today))!)
        }

        // "in X days/weeks/months"
        if let match = text.range(of: #"\bin\s+(\d+)\s+(day|days|week|weeks|month|months)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(text[match])
            if let numMatch = matched.range(of: #"\d+"#, options: .regularExpression) {
                let num = Int(matched[numMatch]) ?? 0
                let unit = matched.lowercased()
                text.removeSubrange(match)
                if unit.contains("day") {
                    return calendar.date(byAdding: .day, value: num, to: today)
                } else if unit.contains("week") {
                    return calendar.date(byAdding: .day, value: num * 7, to: today)
                } else if unit.contains("month") {
                    return calendar.date(byAdding: .month, value: num, to: today)
                }
            }
        }

        // Month day: "jan 15", "january 15", "feb 3", etc.
        let monthPatterns = [
            ("jan(?:uary)?", 1), ("feb(?:ruary)?", 2), ("mar(?:ch)?", 3), ("apr(?:il)?", 4),
            ("may", 5), ("jun(?:e)?", 6), ("jul(?:y)?", 7), ("aug(?:ust)?", 8),
            ("sep(?:tember)?", 9), ("oct(?:ober)?", 10), ("nov(?:ember)?", 11), ("dec(?:ember)?", 12)
        ]
        for (pattern, month) in monthPatterns {
            let regex = "\\b\(pattern)\\s+(\\d{1,2})\\b"
            if let match = text.range(of: regex, options: [.regularExpression, .caseInsensitive]) {
                let matched = String(text[match])
                if let dayMatch = matched.range(of: #"\d{1,2}$"#, options: .regularExpression) {
                    let day = Int(matched[dayMatch]) ?? 1
                    text.removeSubrange(match)
                    var components = calendar.dateComponents([.year], from: today)
                    components.month = month
                    components.day = day
                    if let date = calendar.date(from: components) {
                        // If the date is in the past, use next year
                        return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
                    }
                }
            }
        }

        // M/D format: "1/15", "12/25"
        if let match = text.range(of: #"\b(\d{1,2})/(\d{1,2})\b"#, options: .regularExpression) {
            let matched = String(text[match])
            let parts = matched.split(separator: "/")
            if parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]),
               month >= 1 && month <= 12 && day >= 1 && day <= 31 {
                text.removeSubrange(match)
                var components = calendar.dateComponents([.year], from: today)
                components.month = month
                components.day = day
                if let date = calendar.date(from: components) {
                    return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func matchWord(in text: String, word: String) -> Range<String.Index>? {
        text.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive])
    }

    private static func matchPhrase(in text: String, phrase: String) -> Range<String.Index>? {
        text.range(of: "\\b\(phrase)\\b", options: [.regularExpression, .caseInsensitive])
    }

    private static func nextWeekday(_ weekday: Int, from date: Date) -> Date {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysAhead = weekday - currentWeekday
        if daysAhead <= 0 { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: date)!
    }
}
