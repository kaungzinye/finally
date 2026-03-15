import SwiftUI

struct RecurrencePicker: View {
    @Binding var selection: Recurrence
    var customRule: Binding<RecurrenceRule?>?
    var contextDate: Date?  // The task's due date, used to derive smart defaults
    @Environment(\.dismiss) private var dismiss

    @State private var showCustomEditor = false
    @State private var editingRule: RecurrenceRule = RecurrenceRule()

    var body: some View {
        NavigationStack {
            List {
                // Quick presets
                Section("Presets") {
                    ForEach(Recurrence.presetCases, id: \.self) { recurrence in
                        Button {
                            selection = recurrence
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: recurrence.icon)
                                    .foregroundStyle(recurrence == .none ? Color.secondary : Color.primary)
                                    .frame(width: 24)
                                Text(recurrence.rawValue)
                                Spacer()
                                if selection == recurrence {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // Custom section
                Section("Custom") {
                    if selection == .custom, let rule = customRule?.wrappedValue {
                        // Show current custom rule summary
                        HStack {
                            Image(systemName: "repeat")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text(rule.summary)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }

                    Button {
                        editingRule = customRule?.wrappedValue ?? RecurrenceRule.defaultForDate(contextDate)
                        showCustomEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 24)
                            Text(selection == .custom ? "Edit custom pattern..." : "Create custom pattern...")
                        }
                    }
                }
            }
            .navigationTitle("Recurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showCustomEditor) {
            CustomRecurrenceEditor(
                rule: $editingRule,
                contextDate: contextDate,
                onSave: { savedRule in
                    selection = .custom
                    customRule?.wrappedValue = savedRule
                    showCustomEditor = false
                }
            )
        }
    }
}

// MARK: - Custom Recurrence Editor (Google Calendar-style)

struct CustomRecurrenceEditor: View {
    @Binding var rule: RecurrenceRule
    var contextDate: Date?
    var onSave: (RecurrenceRule) -> Void
    @Environment(\.dismiss) private var dismiss

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    // Calendar weekday indices: 1=Sun, 2=Mon, ..., 7=Sat

    var body: some View {
        NavigationStack {
            List {
                // Repeat every N [units]
                Section {
                    HStack {
                        Text("Repeat every")
                        Stepper(value: $rule.interval, in: 1...99) {
                            Text("\(rule.interval)")
                                .fontWeight(.semibold)
                                .frame(minWidth: 24, alignment: .center)
                        }
                    }

                    Picker("Frequency", selection: $rule.frequency) {
                        ForEach(RecurrenceRule.Frequency.allCases, id: \.self) { freq in
                            Text(rule.interval == 1 ? freq.singularLabel : freq.pluralLabel)
                                .tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Day-of-week selector (weekly only)
                if rule.frequency == .weekly {
                    Section("Repeat on") {
                        HStack(spacing: 8) {
                            ForEach(1...7, id: \.self) { day in
                                Button {
                                    if rule.weekdays.contains(day) {
                                        rule.weekdays.remove(day)
                                    } else {
                                        rule.weekdays.insert(day)
                                    }
                                } label: {
                                    Text(weekdayLabels[day - 1])
                                        .font(.subheadline.weight(.medium))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            rule.weekdays.contains(day)
                                                ? Color.blue
                                                : Color(.systemGray5)
                                        )
                                        .foregroundStyle(
                                            rule.weekdays.contains(day) ? .white : .primary
                                        )
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                    }
                }

                // Monthly mode selector
                if rule.frequency == .monthly {
                    Section("Repeat on") {
                        let dayOfMonth = contextDate.map { Calendar.current.component(.day, from: $0) } ?? 1

                        Button {
                            rule.monthlyMode = .dayOfMonth
                        } label: {
                            HStack {
                                Text("Day \(dayOfMonth) of every month")
                                Spacer()
                                if rule.monthlyMode == .dayOfMonth {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        Button {
                            rule.monthlyMode = .nthWeekday
                            if let date = contextDate {
                                let cal = Calendar.current
                                rule.nthWeekdayOrdinal = cal.component(.weekdayOrdinal, from: date)
                                rule.nthWeekdayDay = cal.component(.weekday, from: date)
                            }
                        } label: {
                            HStack {
                                let ordinal = RecurrenceRule.ordinalName(rule.nthWeekdayOrdinal)
                                let day = RecurrenceRule.fullDayName(rule.nthWeekdayDay)
                                Text("The \(ordinal) \(day)")
                                Spacer()
                                if rule.monthlyMode == .nthWeekday {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        if rule.monthlyMode == .nthWeekday {
                            Picker("Ordinal", selection: $rule.nthWeekdayOrdinal) {
                                Text("1st").tag(1)
                                Text("2nd").tag(2)
                                Text("3rd").tag(3)
                                Text("4th").tag(4)
                                Text("Last").tag(-1)
                            }
                            .pickerStyle(.segmented)

                            Picker("Day", selection: $rule.nthWeekdayDay) {
                                Text("Sun").tag(1)
                                Text("Mon").tag(2)
                                Text("Tue").tag(3)
                                Text("Wed").tag(4)
                                Text("Thu").tag(5)
                                Text("Fri").tag(6)
                                Text("Sat").tag(7)
                            }
                        }
                    }
                }

                // Summary preview
                Section("Preview") {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundStyle(.blue)
                        Text(rule.summary)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Custom Recurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(rule)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
