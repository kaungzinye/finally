import SwiftUI

struct RecurrencePicker: View {
    @Binding var selection: Recurrence
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Recurrence.allCases, id: \.self) { recurrence in
                    Button {
                        selection = recurrence
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: recurrence == .none ? "arrow.counterclockwise.circle" : "repeat")
                                .foregroundStyle(recurrence == .none ? Color.secondary : Color.primary)
                            Text(recurrence.rawValue)
                            Spacer()
                            if selection == recurrence {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recurrence")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
