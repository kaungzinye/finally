import SwiftUI
import SwiftData

/// Displays a time picker for the default notification time used when scheduling
/// reminders on date-only tasks (tasks without a specific time component).
/// Stores the selection as minutes from midnight in UserDefaults.
struct NotificationTimePickerView: View {
    @AppStorage(AppConstants.defaultReminderTimeMinutesKey) private var minutesFromMidnight: Int = AppConstants.defaultReminderTimeMinutes
    @Environment(\.modelContext) private var modelContext

    /// Converts stored minutes-from-midnight to a Date for the DatePicker.
    private var selectedTime: Binding<Date> {
        Binding(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = minutesFromMidnight / 60
                comps.minute = minutesFromMidnight % 60
                comps.second = 0
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let newMinutes = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
                minutesFromMidnight = newMinutes
                // Reschedule all date-only reminders to reflect the new default time
                NotificationService.shared.rescheduleAllReminders(modelContext: modelContext)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Default time",
                    selection: selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
            } header: {
                Text("Default Reminder Time")
            } footer: {
                Text("Reminders on tasks without a specific time will fire at this time on the deadline. Changing this reschedules existing reminders.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Default Reminder Time")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Small inline label showing the currently configured reminder time — used in SettingsView row.
struct DefaultReminderTimeLabel: View {
    @AppStorage(AppConstants.defaultReminderTimeMinutesKey) private var minutesFromMidnight: Int = AppConstants.defaultReminderTimeMinutes

    var body: some View {
        Text(formattedTime)
    }

    private var formattedTime: String {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        guard let date = Calendar.current.date(from: comps) else { return "9:00 AM" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
