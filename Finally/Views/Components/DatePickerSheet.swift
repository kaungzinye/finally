import SwiftUI

/// Picks a task's scheduled day or its deadline. A deadline offers an optional time, and a
/// scheduled day is always a whole day. A scheduled day after the task's deadline day asks to
/// move the deadline too. The sheet's title and VoiceOver label name the field.
struct DatePickerSheet: View {
    enum Field {
        case scheduled, deadline

        var title: String {
            switch self {
            case .scheduled: "Scheduled"
            case .deadline: "Deadline"
            }
        }
    }

    @Binding var selectedDate: Date?
    @Binding var hasTime: Bool
    private let field: Field
    /// The task a scheduled day belongs to, whose deadline a later day asks to move.
    private var task: TaskItem?
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate = Date()
    @State private var pastDeadlineDay: Date?

    init(deadline: Binding<Date?>, hasTime: Binding<Bool>) {
        _selectedDate = deadline
        _hasTime = hasTime
        field = .deadline
    }

    init(scheduledDay: Binding<Date?>, task: TaskItem? = nil) {
        _selectedDate = scheduledDay
        _hasTime = .constant(false)
        field = .scheduled
        self.task = task
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(
                    field.title,
                    selection: $pickerDate,
                    displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Palette.inkControl)
                .accessibilityLabel(field.title)

                if field == .deadline {
                    FilterChip(title: "Add a time", isOn: $hasTime)
                        .accessibilityIdentifier("date-picker-add-time")
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .background(Palette.sheet)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        selectedDate = nil
                        hasTime = false
                        dismiss()
                    }
                }
                ConfirmToolbarButton("Done") {
                    guard field == .scheduled else {
                        selectedDate = pickerDate
                        dismiss()
                        return
                    }
                    let day = Calendar.current.startOfDay(for: pickerDate)
                    if (task?.scheduledDayFit(for: day) ?? .fits) == .fits {
                        selectedDate = day
                        dismiss()
                    } else {
                        pastDeadlineDay = day
                    }
                }
            }
            .deadlineMoveConfirmation(for: task, day: $pastDeadlineDay) { day in
                selectedDate = day
                dismiss()
            }
        }
        .onAppear {
            if let selectedDate {
                pickerDate = selectedDate
            }
        }
        .presentationDetents([.large])
        .paperSheet()
    }
}

extension View {
    /// Asks before a scheduled day after the task's deadline day moves the deadline too, such as
    /// "Monday is after the deadline (Fri). Move the deadline to Monday too?". Move both hands the
    /// day on, and Cancel changes nothing.
    func deadlineMoveConfirmation(for task: TaskItem?, day: Binding<Date?>, onMoveBoth: @escaping (Date) -> Void) -> some View {
        let now = Date()
        let dayName = day.wrappedValue.map { DeadlineMovePrompt.dayName($0, at: now) } ?? ""
        let deadlineName = task.flatMap { TaskRowDate(for: $0, at: now) }.map(\.text) ?? ""
        return alert(
            "Move the deadline to \(dayName) too?",
            isPresented: Binding(get: { day.wrappedValue != nil }, set: { if !$0 { day.wrappedValue = nil } }),
            presenting: day.wrappedValue
        ) { chosen in
            Button("Move both") { onMoveBoth(chosen) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("\(dayName) is after the deadline (\(deadlineName)).")
        }
    }
}

/// How the deadline-move question names a day: "Today", "Tomorrow", a weekday within the week,
/// or its date further out.
enum DeadlineMovePrompt {
    static func dayName(_ date: Date, at referenceDate: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: referenceDate), to: calendar.startOfDay(for: date)).day ?? 0
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        default: return DayMonth.text(for: date, at: referenceDate, calendar: calendar, locale: locale)
        }
    }
}
