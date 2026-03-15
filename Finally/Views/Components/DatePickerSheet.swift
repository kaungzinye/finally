import SwiftUI

struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var pickerDate = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Due Date",
                    selection: $pickerDate,
                    displayedComponents: [.date]
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
