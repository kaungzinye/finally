import SwiftUI

struct InlineReminderPicker: View {
    @Binding var selectedChoices: [ReminderChoice]
    @Environment(\.dismiss) private var dismiss

    @State private var showCustomPicker = false
    @State private var customDate = Date()

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Presets") {
                    ForEach(ReminderOffset.allCases) { offset in
                        let choice = ReminderChoice.preset(offset)
                        Button {
                            if selectedChoices.contains(choice) {
                                selectedChoices.removeAll { $0 == choice }
                            } else {
                                selectedChoices.append(choice)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell")
                                    .foregroundStyle(.orange)
                                Text(offset.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedChoices.contains(choice) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Custom") {
                    Button {
                        showCustomPicker.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                            Text("Pick exact date & time")
                                .foregroundStyle(.primary)
                            Spacer()
                            if showCustomPicker {
                                Image(systemName: "chevron.up")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if showCustomPicker {
                        DatePicker(
                            "Remind at",
                            selection: $customDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)

                        Button {
                            selectedChoices.append(.custom(customDate))
                            showCustomPicker = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("Add Custom Reminder")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }

                    // Show added custom reminders
                    let customChoices = selectedChoices.filter {
                        if case .custom = $0 { return true }
                        return false
                    }
                    ForEach(customChoices) { choice in
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                            Text(choice.displayLabel)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                selectedChoices.removeAll { $0 == choice }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
