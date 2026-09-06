import SwiftUI

struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    @Binding var hasTime: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate = Date()

    init(selectedDate: Binding<Date?>, hasTime: Binding<Bool>) {
        _selectedDate = selectedDate
        _hasTime = hasTime
    }

    var body: some View {
        NavigationStack {
            VStack {
                Toggle("Include Time", isOn: $hasTime)
                    .padding(.horizontal)

                DatePicker(
                    "Due Date",
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
                        selectedDate = pickerDate
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
