import SwiftUI
import SwiftData

/// Picks the default reminder time, the time of day date-level deadline reminders fire.
/// Stores the choice as minutes from midnight.
struct NotificationTimePickerView: View {
    @AppStorage(AppConstants.defaultReminderTimeMinutesKey) private var minutesFromMidnight: Int = AppConstants.defaultReminderTimeMinutes
    @Environment(\.modelContext) private var modelContext

    private static let hours = Array(5...22)
    private static let minutes = [0, 15, 30, 45]

    private var hour: Binding<Int> {
        Binding(
            get: { minutesFromMidnight / 60 },
            set: { save(hour: $0, minute: minutesFromMidnight % 60) }
        )
    }

    private var minute: Binding<Int> {
        Binding(
            get: { minutesFromMidnight % 60 },
            set: { save(hour: minutesFromMidnight / 60, minute: $0) }
        )
    }

    var body: some View {
        List {
            Group {
                Section {
                    ChoiceChips(choices: Self.hours, selection: hour) { Self.hourLabel($0) }
                        .padding(.vertical, 8)
                } header: {
                    SectionLabel("Hour")
                }

                Section {
                    ChoiceChips(choices: Self.minutes, selection: minute) { String(format: ":%02d", $0) }
                        .padding(.vertical, 8)
                } header: {
                    SectionLabel("Minute")
                } footer: {
                    SectionNote("Reminders on a deadline without a time fire at \(DefaultReminderTimeLabel.text(minutesFromMidnight)). Changing it moves the reminders you already have.")
                }
            }
            .cardRow()
        }
        .paperList()
        .navigationTitle("Default reminder time")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(hour: Int, minute: Int) {
        minutesFromMidnight = hour * 60 + minute
        NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
    }

    private static func hourLabel(_ hour: Int) -> String {
        DefaultReminderTimeLabel.date(minutesFromMidnight: hour * 60)
            .formatted(.dateTime.hour())
    }
}

/// The configured default reminder time, for the Settings row.
struct DefaultReminderTimeLabel: View {
    @AppStorage(AppConstants.defaultReminderTimeMinutesKey) private var minutesFromMidnight: Int = AppConstants.defaultReminderTimeMinutes

    var body: some View {
        Text(Self.text(minutesFromMidnight))
    }

    static func text(_ minutesFromMidnight: Int) -> String {
        date(minutesFromMidnight: minutesFromMidnight).formatted(date: .omitted, time: .shortened)
    }

    static func date(minutesFromMidnight: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutesFromMidnight / 60, minute: minutesFromMidnight % 60, second: 0, of: Date()
        ) ?? Date()
    }
}
