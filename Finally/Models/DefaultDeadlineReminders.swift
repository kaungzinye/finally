import Foundation

/// The deadline reminders a task receives when its deadline goes from empty to set.
/// The list is a phone setting and never travels to a provider.
struct DefaultDeadlineReminders: Equatable, Sendable {
    var offsets: [DeadlineReminderOffset]

    static let standard = DefaultDeadlineReminders(offsets: [.morningOf, .daysBefore(1), .weeksBefore(1), .hourBefore])

    static func current(in settings: UserDefaults = .standard) -> DefaultDeadlineReminders {
        settings.string(forKey: AppConstants.defaultDeadlineRemindersKey).flatMap(Self.init(rawValue:)) ?? .standard
    }

    func save(in settings: UserDefaults = .standard) {
        settings.set(rawValue, forKey: AppConstants.defaultDeadlineRemindersKey)
    }

    /// The offsets that apply to a deadline. `hourBefore` applies only to a timed deadline.
    func offsets(deadlineHasTime: Bool) -> [DeadlineReminderOffset] {
        offsets.filter { deadlineHasTime || $0 != .hourBefore }
    }

    /// What the + chip offers in Settings: the short list minus the current defaults.
    var addableOffsets: [DeadlineReminderOffset] {
        DeadlineReminderOffset.menu.filter { !offsets.contains($0) }
    }

    mutating func add(_ offset: DeadlineReminderOffset) {
        guard offset.isValid, !offsets.contains(offset) else { return }
        offsets.append(offset)
    }

    mutating func remove(_ offset: DeadlineReminderOffset) {
        offsets.removeAll { $0 == offset }
    }
}

/// Settings stores the list as JSON text, which `@AppStorage` reads directly.
extension DefaultDeadlineReminders: RawRepresentable {
    init?(rawValue: String) {
        guard let offsets = try? JSONDecoder().decode([DeadlineReminderOffset].self, from: Data(rawValue.utf8)) else { return nil }
        self.offsets = offsets
    }

    var rawValue: String {
        let data = (try? JSONEncoder().encode(offsets)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
