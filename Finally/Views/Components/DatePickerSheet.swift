import SwiftUI

/// Picks a date. Passing `hasTime` offers an optional time, and omitting it picks a whole day.
struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    @Binding var hasTime: Bool
    private let offersTime: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate = Date()

    init(selectedDate: Binding<Date?>, hasTime: Binding<Bool>) {
        _selectedDate = selectedDate
        _hasTime = hasTime
        offersTime = true
    }

    init(selectedDate: Binding<Date?>) {
        _selectedDate = selectedDate
        _hasTime = .constant(false)
        offersTime = false
    }

    var body: some View {
        NavigationStack {
            VStack {
                if offersTime {
                    Toggle("Include Time", isOn: $hasTime)
                        .padding(.horizontal)
                }

                DatePicker(
                    "Deadline",
                    selection: $pickerDate,
                    displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle("Select Date")
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
                        selectedDate = offersTime ? pickerDate : Calendar.current.startOfDay(for: pickerDate)
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
        .presentationDetents([.medium])
    }
}
