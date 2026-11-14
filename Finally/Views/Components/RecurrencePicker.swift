import SwiftUI

struct RecurrencePicker: View {
    @Binding var selection: Recurrence
    var customRule: Binding<RecurrenceRule?>?
    var contextDate: Date?  // The task's deadline, used to derive smart defaults
    @Environment(\.dismiss) private var dismiss

    @State private var showCustomEditor = false
    @State private var editingRule: RecurrenceRule = RecurrenceRule()

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(Recurrence.presetCases, id: \.self) { recurrence in
                            CheckRow(isSelected: selection == recurrence, action: {
                                selection = recurrence
                                dismiss()
                            }) {
                                Image(systemName: recurrence.icon)
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 24)
                                Text(recurrence == .none ? "Doesn't repeat" : recurrence.rawValue)
                            }
                        }
                    }

                    Section {
                        if selection == .custom, let rule = customRule?.wrappedValue {
                            CheckRow(isSelected: true, action: {}) {
                                Image(systemName: "repeat")
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 24)
                                Text(rule.summary)
                            }
                        }

                        Button {
                            editingRule = customRule?.wrappedValue ?? RecurrenceRule.defaultForDate(contextDate)
                            showCustomEditor = true
                        } label: {
                            Label(selection == .custom ? "Change your own pattern" : "Make your own pattern", systemImage: "slider.horizontal.3")
                                .foregroundStyle(Palette.ink)
                        }
                    } header: {
                        SectionLabel("Your own")
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ConfirmToolbarButton("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .paperSheet()
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

// MARK: - Custom recurrence editor

struct CustomRecurrenceEditor: View {
    @Binding var rule: RecurrenceRule
    var contextDate: Date?
    var onSave: (RecurrenceRule) -> Void
    @Environment(\.dismiss) private var dismiss

    // Calendar weekday indices: 1=Sun, 2=Mon, ..., 7=Sat
    private static let weekdays = Array(1...7)
    private static let ordinals = [1, 2, 3, 4, -1]

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        HStack(spacing: 12) {
                            Text("Every")
                                .foregroundStyle(Palette.ink)
                            stepButton("minus", label: "Fewer") { rule.interval = max(1, rule.interval - 1) }
                                .disabled(rule.interval <= 1)
                            Text("\(rule.interval)")
                                .font(.action)
                                .foregroundStyle(Palette.ink)
                                .frame(minWidth: 28)
                                .accessibilityLabel("Every \(rule.interval)")
                            stepButton("plus", label: "More") { rule.interval = min(99, rule.interval + 1) }
                                .disabled(rule.interval >= 99)
                            Spacer()
                        }
                        ChoiceChips(choices: RecurrenceRule.Frequency.allCases, selection: $rule.frequency) {
                            rule.interval == 1 ? $0.singularLabel : $0.pluralLabel
                        }
                        .padding(.vertical, 4)
                    } header: {
                        SectionLabel("Repeat")
                    }

                    if rule.frequency == .weekly {
                        Section {
                            HStack(spacing: 8) {
                                ForEach(Self.weekdays, id: \.self) { day in
                                    weekdayButton(day)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                        } header: {
                            SectionLabel("On")
                        }
                    }

                    if rule.frequency == .monthly {
                        Section {
                            let dayOfMonth = contextDate.map { Calendar.current.component(.day, from: $0) } ?? 1

                            CheckRow(isSelected: rule.monthlyMode == .dayOfMonth, action: { rule.monthlyMode = .dayOfMonth }) {
                                Text("Day \(dayOfMonth) of every month")
                            }

                            CheckRow(isSelected: rule.monthlyMode == .nthWeekday, action: chooseNthWeekday) {
                                Text("The \(RecurrenceRule.ordinalName(rule.nthWeekdayOrdinal)) \(RecurrenceRule.fullDayName(rule.nthWeekdayDay))")
                            }

                            if rule.monthlyMode == .nthWeekday {
                                ChoiceChips(choices: Self.ordinals, selection: $rule.nthWeekdayOrdinal) {
                                    $0 == -1 ? "Last" : RecurrenceRule.ordinalName($0)
                                }
                                .padding(.vertical, 4)
                                ChoiceChips(choices: Self.weekdays, selection: $rule.nthWeekdayDay) {
                                    RecurrenceRule.shortDayName($0) ?? ""
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            SectionLabel("On")
                        }
                    }

                    Section {
                        Label(rule.summary, systemImage: "repeat")
                            .foregroundStyle(Palette.ink)
                    } header: {
                        SectionLabel("Repeats")
                    }
                }
                .cardRow()
            }
            .paperList(background: Palette.sheet)
            .navigationTitle("Your own pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ConfirmToolbarButton("Save") {
                    onSave(rule)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .paperSheet()
    }

    private func chooseNthWeekday() {
        rule.monthlyMode = .nthWeekday
        if let date = contextDate {
            let calendar = Calendar.current
            rule.nthWeekdayOrdinal = calendar.component(.weekdayOrdinal, from: date)
            rule.nthWeekdayDay = calendar.component(.weekday, from: date)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.chip)
                .foregroundStyle(Palette.ink)
                .frame(width: 38, height: 34)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func weekdayButton(_ day: Int) -> some View {
        let isOn = rule.weekdays.contains(day)
        return Button {
            if isOn {
                rule.weekdays.remove(day)
            } else {
                rule.weekdays.insert(day)
            }
        } label: {
            Text(String(RecurrenceRule.shortDayName(day)?.prefix(1) ?? ""))
                .font(.chip)
                .frame(width: 36, height: 36)
                .background(isOn ? Palette.ink : Palette.wash, in: Circle())
                .foregroundStyle(isOn ? Palette.onInk : Palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RecurrenceRule.fullDayName(day))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
