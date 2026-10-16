import SwiftUI

/// Edits the default deadline reminders every new deadline receives.
struct DefaultDeadlineRemindersView: View {
    @AppStorage(AppConstants.defaultDeadlineRemindersKey) private var defaults = DefaultDeadlineReminders.standard

    var body: some View {
        List {
            Section {
                FlowLayout(spacing: 8) {
                    ForEach(defaults.offsets, id: \.self) { offset in
                        RemovableChip(label: offset.label, icon: "bell") {
                            defaults.remove(offset)
                        }
                    }
                    if !defaults.addableOffsets.isEmpty {
                        AddChipMenu(
                            choices: defaults.addableOffsets,
                            title: \.label,
                            accessibilityLabel: "Add default reminder"
                        ) { offset in
                            defaults.add(offset)
                        }
                        .accessibilityIdentifier("add-default-reminder")
                    }
                }
                .padding(.vertical, 8)
            } header: {
                SectionLabel("New deadlines get")
            } footer: {
                Text("A task receives these when it first gains a deadline, and you can change them on the task. Day reminders fire at the default reminder time. 1 hour before applies only to deadlines with a time.")
                    .font(.meta)
                    .foregroundStyle(Palette.muted)
            }
            .cardRow()
        }
        .paperList()
        .navigationTitle("Deadline reminders")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The number of default deadline reminders, for the Settings row.
struct DefaultDeadlineRemindersLabel: View {
    @AppStorage(AppConstants.defaultDeadlineRemindersKey) private var defaults = DefaultDeadlineReminders.standard

    var body: some View {
        Text(defaults.offsets.isEmpty ? "None" : "\(defaults.offsets.count)")
    }
}
