import SwiftUI

/// Picks a task's scheduled day or its deadline. A deadline offers an optional time, and a
/// scheduled day is always a whole day. The sheet's title and VoiceOver label name the field.
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
    /// The last day a scheduled day may take: its task's deadline.
    private var latest: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate = Date()

    init(deadline: Binding<Date?>, hasTime: Binding<Bool>) {
        _selectedDate = deadline
        _hasTime = hasTime
        field = .deadline
    }

    init(scheduledDay: Binding<Date?>, latest: Date? = nil) {
        _selectedDate = scheduledDay
        _hasTime = .constant(false)
        field = .scheduled
        self.latest = latest
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(
                    field.title,
                    selection: $pickerDate,
                    in: Date.distantPast...(latest ?? .distantFuture),
                    displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Palette.ink)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedDate = field == .deadline ? pickerDate : Calendar.current.startOfDay(for: pickerDate)
                        dismiss()
                    }
                }
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
