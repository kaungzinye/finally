import SwiftUI

struct PriorityPicker: View {
    @Binding var selection: TaskPriority?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "flag")
                            .foregroundStyle(.secondary)
                        Text("No Priority")
                        Spacer()
                        if selection == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button {
                        selection = priority
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: priority.icon)
                                .foregroundStyle(priority.color)
                            Text(priority.rawValue)
                            Spacer()
                            if selection == priority {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Priority")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
